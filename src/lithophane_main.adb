------------------------------------------------------------------------------
--  lithophane_main.adb
--
--  Program entry point. Drives the whole pipeline:
--    * parse the command line (GNAT.Command_Line) and print help/version;
--    * load the input image with GID into a raw 24-bit RGB bitmap;
--    * convert it to a greyscale colour matrix (optionally saved as PGM);
--    * pick and apply the requested filter (bartlett, gauss, square,
--      sharpen, threshold), optionally overridden by a TOML config;
--    * build the mesh via Lithophane.Calculate_Facets and write it out as
--      binary STL, ASCII STL and/or 3MF.
--
--  Created : 2026-08-23
--  Author  : Simon Beàn
------------------------------------------------------------------------------

with GID;
with Ada.Calendar;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Command_Line;        use Ada.Command_Line;
with Ada.Exceptions;          use Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;   use Ada.Streams.Stream_IO;
with Ada.Text_IO;             use Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Ada.Strings.Unbounded;
with GNAT.Command_Line;       use GNAT.Command_Line;

with Interfaces;

with Lithophane;         use Lithophane;
with Lithophane.STL;     use Lithophane.STL;
with Lithophane.File3mf; use Lithophane.File3mf;
with Lithophane.Filters; use Lithophane.Filters;

procedure Lithophane_Main is

   Lithophane_Version : constant String := "1.0.0";

   procedure Version is
   begin
      Put_Line (Standard_Error, "Lithophane " & Lithophane_Version);
   end Version;

   procedure Help is
   begin
      Version;
      Put_Line (Standard_Error, "Usage: lithophane [options] <input_file>");
      Put_Line (Standard_Error, "Options:");
      Put_Line (Standard_Error, "-h --help");
      Put_Line
        (Standard_Error,
         "-f<a_filter> --filter <a_filter> [<n>] ; <a_filter> is one of"
         & " bartlett, gauss, square, sharpen, threshold. The optional <n>"
         & " that follows is the filter size (odd number) or, for the"
         & " threshold filter, the threshold value 0 .. 255."
         & " Example: lithophane --filter gauss 5 image.png");
      Put_Line (Standard_Error, "-b --save-binary");
      Put_Line (Standard_Error, "-a --save-ascii");
      Put_Line (Standard_Error, "-m --save-3mf");
      Put_Line (Standard_Error, "-p --save-pgm");
      Put_Line (Standard_Error, "-o<a_filename> --output-name=<a_filename>");
      Put_Line (Standard_Error, "-B<a_border> --border=<a_border>");
      Put_Line
        (Standard_Error,
         "--dimensions=<W>x<H>x<D> ; target 3MF size in mm; an empty or 0"
         & " component leaves that axis proportional."
         & " Example: --dimensions=100x100x1.5");
      Put_Line
        (Standard_Error,
         "-c<a_config_file> --config=<a_config_file> ; note:  it overwrites"
         & " previous options");
   end Help;

   --  Raised once a fatal, user-facing problem has been reported (the
   --  human-readable diagnostic is printed by Fail before the exception is
   --  propagated). The top-level handler turns it into a non-zero exit
   --  status without dumping a raw exception trace on the user.
   Fatal_Error : exception;

   procedure Fail (Message : String) is
   begin
      Put_Line (Standard_Error, "Error: " & Message);
      raise Fatal_Error;
   end Fail;

   --  Close F if it is still open, swallowing any secondary error so the
   --  original problem is the one that reaches the user.
   procedure Close_If_Open (F : in out Ada.Streams.Stream_IO.File_Type) is
   begin
      if Is_Open (F) then
         Close (F);
      end if;
   exception
      when others =>
         null;
   end Close_If_Open;

   use Interfaces;

   type Byte_Array is array (Integer range <>) of Unsigned_8;
   type p_Byte_Array is access Byte_Array;

   procedure Dispose is new
     Ada.Unchecked_Deallocation (Byte_Array, p_Byte_Array);

   img_buf : p_Byte_Array := null;

   --  Load image into a 24-bit truecolor RGB raw bitmap (for a PPM output)
   procedure Load_Raw_Image
     (image      : in out GID.Image_Descriptor;
      buffer     : in out p_Byte_Array;
      next_frame : out Ada.Calendar.Day_Duration)
   is
      subtype Primary_color_range is Unsigned_8;
      image_width  : constant Positive := GID.Pixel_Width (image);
      image_height : constant Positive := GID.Pixel_Height (image);
      idx          : Natural;
      --
      procedure Set_X_Y (x, y : Natural) is
      begin
         idx := 3 * (x + image_width * y);
      end Set_X_Y;
      --
      procedure Put_Pixel
        (red, green, blue : Primary_color_range; alpha : Primary_color_range)
      is
         pragma Warnings (off, alpha); -- alpha is just ignored
      begin
         buffer (idx .. idx + 2) := [red, green, blue];
         idx := idx + 3;
         --  ^GID requires us to look to next pixel on the right for next time.
      end Put_Pixel;

      stars : Natural := 0;
      procedure Feedback (percents : Natural) is
         so_far : constant Natural := percents / 5;
      begin
         for i in stars + 1 .. so_far loop
            Put (Standard_Error, '*');
         end loop;
         stars := so_far;
      end Feedback;

      procedure Load_Image is new
        GID.Load_Image_Contents
          (Primary_color_range,
           Set_X_Y,
           Put_Pixel,
           Feedback,
           GID.fast);

   begin
      Dispose (buffer);
      buffer := new Byte_Array (0 .. 3 * image_width * image_height - 1);
      Load_Image (image, next_frame);
   end Load_Raw_Image;

   procedure Dump_PGM
     (name : String; i : GID.Image_Descriptor; the_image : Matrix_Access)
   is
      F : Ada.Text_IO.File_Type;
   begin
      Create (F, Out_File, name & ".pgm");
      --  PPM Header:
      Put_Line (F, "P2");
      Put_Line
        (F,
         Integer'Image (GID.Pixel_Height (i))
         & " "
         & Integer'Image (GID.Pixel_Width (i)));
      Put_Line (F, "255");
      Print_Matrix (the_image, F);
      Close (F);
   exception
      when E : others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         Fail
           ("cannot write PGM file """
            & name
            & ".pgm"": "
            & Exception_Message (E));
   end Dump_PGM;

   --
   --  Process_Image
   --
   procedure Process_Image
     (the_image : Matrix_Access; Settings : Settings_Record) is
   begin

      --  apply a filter
      case Settings.filter is
         when bartlett  =>
            Apply_Filter
              (the_image,
               Create_Bartlett_Filter
                 (Settings.filter_size, Settings.filter_size));

         when gauss     =>
            Apply_Filter
              (the_image,
               Create_Gauss_Filter
                 (Settings.filter_size, Settings.filter_size));

         when square    =>
            Apply_Filter
              (the_image,
               Create_Square_Filter
                 (Settings.filter_size, Settings.filter_size));

         when sharpen   =>
            Apply_Filter
              (the_image,
               Create_Sharpen_Filter
                 (Settings.filter_size, Settings.filter_size));

         when threshold =>
            Apply_Threshold_Filter (the_image, Settings.filter_threshold);
      end case;

   end Process_Image;

   --
   --  Generate_Lithophane
   --
   procedure Generate_Lithophane (Settings : Settings_Record) is

      F          : Ada.Streams.Stream_IO.File_Type;
      img_descrp : GID.Image_Descriptor;
      up_name    : constant String :=
        To_Upper (Ada.Strings.Unbounded.To_String (Settings.filename));
      next_frame : Ada.Calendar.Day_Duration := 0.0;

      c           : Positive := 1;
      l           : Positive := 1;
      x           : Integer := 0;
      rouge       : Color_Type := 0;
      bleu        : Color_Type := 0;
      vert        : Color_Type := 0;
      grey        : Color_Type := 0;
      Facets_List : Facets.Vector;
   begin
      Open (F, In_File, Ada.Strings.Unbounded.To_String (Settings.filename));
      Put_Line
        (Standard_Error,
         "Processing image file: "
         & Ada.Strings.Unbounded.To_String (Settings.filename)
         & "...");

      GID.Load_Image_Header
        (img_descrp,  --  in out
         Stream (F).all,  --  stream; reads the file's content
         try_tga =>
           Ada.Strings.Unbounded.To_String (Settings.filename)'Length >= 4
           and then up_name (up_name'Last - 3 .. up_name'Last) = ".TGA");

      Load_Raw_Image (img_descrp, img_buf, next_frame);

      New_Line;
      Put_Line
        (Standard_Error,
         "  WIDTH  " & Integer'Image (GID.Pixel_Width (img_descrp)));
      Put_Line
        (Standard_Error,
         "  HEIGHT " & Integer'Image (GID.Pixel_Height (img_descrp)));
      Put_Line (Standard_Error, "  F " & Integer'Image (img_buf'First));
      Put_Line (Standard_Error, "  L " & Integer'Image (img_buf'Last));
      declare
         matr       : constant Matrix_Access :=
           new Matrix_Type
                 (1 .. GID.Pixel_Width (img_descrp) + 2 * Settings.border,
                  1 .. GID.Pixel_Height (img_descrp) + 2 * Settings.border);
         matg       : constant Matrix_Access :=
           new Matrix_Type
                 (1 .. GID.Pixel_Width (img_descrp) + 2 * Settings.border,
                  1 .. GID.Pixel_Height (img_descrp) + 2 * Settings.border);
         matb       : constant Matrix_Access :=
           new Matrix_Type
                 (1 .. GID.Pixel_Width (img_descrp) + 2 * Settings.border,
                  1 .. GID.Pixel_Height (img_descrp) + 2 * Settings.border);
         matgrey    : constant Matrix_Access :=
           new Matrix_Type
                 (1 .. GID.Pixel_Width (img_descrp) + 2 * Settings.border,
                  1 .. GID.Pixel_Height (img_descrp) + 2 * Settings.border);
         tempString : String (1 .. 3);
      begin
         Put_Line ("IMGBUF " & img_buf'First'Img);
         for i in matr'Range (1) loop
            for j in matr'Range (2) loop
               matr (i, j) := 255;
               matg (i, j) := 255;
               matb (i, j) := 255;
               matgrey (i, j) := 255;
            end loop;
         end loop;

         while x <= img_buf'Last loop
            matr (c + Settings.border, l + Settings.border) :=
              Color_Type (img_buf (x));
            rouge := Color_Type (img_buf (x));
            --  (Standard_Error, 'r');
            x := x + 1;
            if x <= img_buf'Last then
               matg (c + Settings.border, l + Settings.border) :=
                 Color_Type (img_buf (x));
               vert := Color_Type (img_buf (x));
               --  Put (Standard_Error, 'b');
               x := x + 1;
               if x <= img_buf'Last then
                  matb (c + Settings.border, l + Settings.border) :=
                    Color_Type (img_buf (x));
                  bleu := Color_Type (img_buf (x));
               --  Put (Standard_Error, 'g');

               end if;
            end if;
            grey :=
              255
              - Color_Type
                  (0.2989 * Float (rouge) + 0.5870 * Float (vert)
                   + 0.1140 * Float (bleu));
            --  Put_Line ("GREY " & grey'Img);
            matgrey (c + Settings.border, l + Settings.border) := grey;

            img_buf (x - 2) := Unsigned_8 (grey);
            img_buf (x - 1) := Unsigned_8 (grey);
            img_buf (x) := Unsigned_8 (grey);
            x := x + 1;
            if c mod GID.Pixel_Width (img_descrp) = 0 then
               c := 1; --  Put(Standard_Error," c=1");
               l := l + 1; --  Put(Standard_Error,"+l");

            else
               c := c + 1; --  Put(Standard_Error," +c");
            end if;

         end loop;

         Process_Image (matgrey, Settings);
         Facets_List := Calculate_Facets (matgrey);

         if Settings.save_as_ascii then
            Dump_STL_ASCII (Facets_List, Settings);
         end if;

         if Settings.save_as_binary then
            Dump_STL_BIN (Facets_List, Settings);
         end if;

         if Settings.save_as_3mf then
            Dump_3mf (Facets_List, Settings);
         end if;

         if Settings.save_pgm then
            Dump_PGM
              (Ada.Strings.Unbounded.To_String (Settings.outfilename),
               img_descrp,
               matgrey);
         end if;

      end;

      --  printBuffer(i);
      Close (F);

   exception
      when Fatal_Error =>
         --  Already reported (e.g. by Dump_PGM); just release the file.
         Close_If_Open (F);
         raise;

      when Ada.IO_Exceptions.Name_Error =>
         Close_If_Open (F);
         Fail
           ("cannot open input image file """
            & Ada.Strings.Unbounded.To_String (Settings.filename)
            & """ (no such file)");

      when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Status_Error =>
         Close_If_Open (F);
         Fail
           ("cannot read input image file """
            & Ada.Strings.Unbounded.To_String (Settings.filename)
            & """ (permission denied or file in use)");

      when GID.unknown_image_format =>
         Close_If_Open (F);
         Fail
           ("""" & Ada.Strings.Unbounded.To_String (Settings.filename)
            & """ is not in an image format GID recognises");

      when GID.known_but_unsupported_image_format
         | GID.unsupported_image_subformat =>
         Close_If_Open (F);
         Fail
           ("the image format of """
            & Ada.Strings.Unbounded.To_String (Settings.filename)
            & """ is recognised but not supported");

      when GID.error_in_image_data =>
         Close_If_Open (F);
         Fail
           ("the image file """
            & Ada.Strings.Unbounded.To_String (Settings.filename)
            & """ is corrupt or truncated");

      when Storage_Error =>
         Close_If_Open (F);
         Fail
           ("not enough memory to process """
            & Ada.Strings.Unbounded.To_String (Settings.filename)
            & """ (image too large?)");

      when E : others =>
         Close_If_Open (F);
         Fail
           ("failed to generate the lithophane for """
            & Ada.Strings.Unbounded.To_String (Settings.filename)
            & """: "
            & Exception_Name (E)
            & " - "
            & Exception_Message (E));
   end Generate_Lithophane;

   Settings : Settings_Record;

   --  Set as soon as a --filter/-f switch is seen. It tells the code after the
   --  Getopt loop that the next positional argument (if it is a number) is the
   --  filter parameter: filter_threshold for the threshold filter, filter_size
   --  for every other filter. Example: lithophane --filter gauss 5 image.png
   Filter_Given : Boolean := False;

   --  Decode a --filter/-f value into Settings.filter. An unknown name would
   --  otherwise leak a bare Constraint_Error out of Filters_Choice'Value.
   procedure Set_Filter (Name : String) is
   begin
      Settings.filter := Lithophane.Filters_Choice'Value (Name);
      Filter_Given := True;
   exception
      when Constraint_Error =>
         Fail
           ("unknown filter """
            & Name
            & """; expected one of bartlett, gauss, square, sharpen,"
            & " threshold");
   end Set_Filter;

   --  Decode a --border/-B value into Settings.border, rejecting anything
   --  that is not a plain non-negative integer.
   procedure Set_Border (Spec : String) is
   begin
      Settings.border := Natural'Value (Spec);
   exception
      when Constraint_Error =>
         Fail
           ("invalid border value """
            & Spec
            & """; expected a non-negative integer");
   end Set_Border;

   --  Read the numeric argument that follows a --filter switch, if any, and
   --  store it in the relevant Settings field. When the next argument is not a
   --  plain number it is the input file name instead, so keep it for later.
   procedure Get_Filter_Argument is
      Extra : constant String := Get_Argument;
   begin
      if Extra = "" then
         return;
      elsif (for all C of Extra => C in '0' .. '9') then
         if Settings.filter = Lithophane.threshold
           and then Color_Type'Value (Extra) >= 0
           and then Color_Type'Value (Extra) <= 255
         then
            Settings.filter_threshold := Color_Type'Value (Extra);
            Put_Line ("Filter threshold =" & Settings.filter_threshold'Img);
         elsif Natural'Value (Extra) >= 3
           and then Natural'Value (Extra) mod 2 = 1
         then
            Settings.filter_size := Natural'Value (Extra);
            Put_Line ("Filter size =" & Settings.filter_size'Img);
         end if;
      else
         Settings.filename :=
           Ada.Strings.Unbounded.To_Unbounded_String (Extra);
      end if;
   exception
      when Constraint_Error =>
         --  Extra is all digits but does not fit the target type; treat it
         --  as "no valid parameter given" and keep the defaults.
         Put_Line
           (Standard_Error,
            "ignoring out-of-range filter argument: " & Extra);
   end Get_Filter_Argument;

   --  Parse a "--dimensions=WxHxD" value into Settings.dimensions (in mm,
   --  applied only to the 3MF output). Any component may be left empty or
   --  set to 0 to leave that axis unconstrained, e.g. "--dimensions=100x100x"
   --  fixes width and height and lets the depth follow proportionally.
   procedure Parse_Dimensions (Spec : String) is
      Start : Positive := Spec'First;
      Axis  : Natural := 0;

      procedure Take (S : String) is
         Val : Float := 0.0;
      begin
         if S /= "" then
            begin
               Val := Float'Value (S);
            exception
               when others =>
                  Put_Line (Standard_Error, "ignoring bad dimension: " & S);
                  Val := 0.0;
            end;
         end if;
         case Axis is
            when 0      =>
               Settings.dimensions.width := Val;

            when 1      =>
               Settings.dimensions.height := Val;

            when 2      =>
               Settings.dimensions.depth := Val;

            when others =>
               null;
         end case;
         Axis := Axis + 1;
      end Take;
   begin
      for I in Spec'Range loop
         if Spec (I) in 'x' | 'X' then
            Take (Spec (Start .. I - 1));
            Start := I + 1;
         end if;
      end loop;
      Take (Spec (Start .. Spec'Last));
      Put_Line
        (Standard_Error,
         "Dimensions (mm): "
         & Settings.dimensions.width'Img
         & " x"
         & Settings.dimensions.height'Img
         & " x"
         & Settings.dimensions.depth'Img);
   end Parse_Dimensions;

begin
   if Argument_Count < 1 then
      Help;
      return;
   end if;

   loop
      case Getopt
             ("h -help v -version f: -filter= b -save-binary a -save-ascii"
              & " m -save-3mf p -save-pgm o: -output-name="
              & " B: -border= c: -config= -dimensions=")
      is
         when 'h'    =>
            Put_Line ("Get help");
            Help;
            return;

         when 'v'    =>
            Version;
            return;

         when 'f'    =>
            Put_Line ("Seen -f with arg=" & Parameter);
            Set_Filter (Parameter);

         when 'b'    =>
            Put_Line ("Save stl-bin");
            Settings.save_as_binary := True;

         when 'a'    =>
            Put_Line ("Save stl-acii");
            Settings.save_as_ascii := True;

         when 'm'    =>
            Put_Line ("Save 3mf");
            Settings.save_as_3mf := True;

         when 'p'    =>
            Settings.save_pgm := True;

         when 'o'    =>
            Settings.outfilename :=
              Ada.Strings.Unbounded.To_Unbounded_String (Parameter);

         when 'B'    =>
            Put_Line ("Border");
            Set_Border (Parameter);

         when 'c'    =>
            Settings.config :=
              Ada.Strings.Unbounded.To_Unbounded_String (Parameter);
            Put_Line
              ("Config file : "
               & Ada.Strings.Unbounded.To_String (Settings.config));
            Parse_Config (Settings);

         when '-'    =>
            if Full_Switch = "-help" then
               Put_Line ("Seen --help");
               Help;
               return;
            elsif Full_Switch = "-version" then
               Version;
            elsif Full_Switch = "-filter" then
               Put_Line ("Seen --filter with arg=" & Parameter);
               Set_Filter (Parameter);
            elsif Full_Switch = "-save-binary" then
               Put_Line ("Seen --save-binary");
               Settings.save_as_binary := True;
            elsif Full_Switch = "-save-ascii" then
               Put_Line ("Seen --save-ascii");
               Settings.save_as_ascii := True;
            elsif Full_Switch = "-save-3mf" then
               Put_Line ("Seen --save-3mf");
               Settings.save_as_3mf := True;
            elsif Full_Switch = "-border" then
               Set_Border (Parameter);
               Put_Line ("Seen --border with arg=" & Settings.border'Img);
            elsif Full_Switch = "-output-name" then
               Settings.outfilename :=
                 Ada.Strings.Unbounded.To_Unbounded_String (Parameter);
            elsif Full_Switch = "-save-pgm" then
               Settings.save_pgm := True;
            elsif Full_Switch = "-config" then
               Settings.config :=
                 Ada.Strings.Unbounded.To_Unbounded_String (Parameter);
               Parse_Config (Settings);
            elsif Full_Switch = "-dimensions" then
               Parse_Dimensions (Parameter);
            end if;

         when others =>
            exit;
      end case;
   end loop;
   if Filter_Given then
      Get_Filter_Argument;
   end if;

   if Ada.Strings.Unbounded.Length (Settings.filename) = 0 then
      Settings.filename :=
        Ada.Strings.Unbounded.To_Unbounded_String (Get_Argument);
   end if;

   if Ada.Strings.Unbounded.Length (Settings.filename) = 0 then
      New_Line (Standard_Error);
      Put_Line (Standard_Error, "Error: no input image file given.");
      New_Line (Standard_Error);
      Help;
      Set_Exit_Status (Failure);
      return;
   end if;

   Generate_Lithophane (Settings);

exception
   when Fatal_Error =>
      --  A human-readable diagnostic has already been printed by Fail.
      Set_Exit_Status (Failure);

   when GNAT.Command_Line.Invalid_Switch =>
      New_Line (Standard_Error);
      Put_Line
        (Standard_Error,
         "Error: invalid command line switch: " & Full_Switch);
      New_Line (Standard_Error);
      Help;
      Set_Exit_Status (Failure);

   when GNAT.Command_Line.Invalid_Parameter =>
      New_Line (Standard_Error);
      Put_Line
        (Standard_Error,
         "Error: missing parameter for switch: " & Full_Switch);
      New_Line (Standard_Error);
      Help;
      Set_Exit_Status (Failure);

   when E : others =>
      Put_Line
        (Standard_Error,
         "Unexpected error: "
         & Exception_Name (E)
         & " - "
         & Exception_Message (E));
      Set_Exit_Status (Failure);
end Lithophane_Main;
