with GID;
with Ada.Calendar;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Command_Line;        use Ada.Command_Line;
with Ada.Streams.Stream_IO;   use Ada.Streams.Stream_IO;
with Ada.Text_IO;             use Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Ada.Strings.Unbounded;
with GNAT.Command_Line;       use GNAT.Command_Line;

with Interfaces;

with Lithophane;         use Lithophane;
with Lithophane.STL;     use Lithophane.STL;
with Lithophane.Filters; use Lithophane.Filters;

procedure Lithophane_Main is

   Lithophane_Version : constant String := "0.1.2";

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
      --  Put_Line (Standard_Error, "-f<a_filter> --filter=<a_filter>");
      Put_Line (Standard_Error, "-b --save-binary");
      Put_Line (Standard_Error, "-a --save-ascii");
      Put_Line (Standard_Error, "-p --save-pgm");
      Put_Line (Standard_Error, "-o<a_filename> --output-name=<a_filename>");
      Put_Line (Standard_Error, "-H<a_height> --height=<a_height>");
      Put_Line
        (Standard_Error,
         "-c<a_config_file> --config=<a_config_file> ; note:  it overwrites"
         & " previous options");
   end Help;

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
   --  PreProcess_Image
   --
   procedure PreProcess_Image (Settings : Settings_Record) is

      F          : Ada.Streams.Stream_IO.File_Type;
      img_descrp : GID.Image_Descriptor;
      up_name    : constant String :=
        To_Upper (Ada.Strings.Unbounded.To_String (Settings.filename));
      next_frame : Ada.Calendar.Day_Duration := 0.0;

      c     : Positive := 1;
      l     : Positive := 1;
      x     : Integer := 0;
      rouge : Color_Type := 0;
      bleu  : Color_Type := 0;
      vert  : Color_Type := 0;
      grey  : Color_Type := 0;
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
                 (1 .. GID.Pixel_Width (img_descrp),
                  1 .. GID.Pixel_Height (img_descrp));
         matg       : constant Matrix_Access :=
           new Matrix_Type
                 (1 .. GID.Pixel_Width (img_descrp),
                  1 .. GID.Pixel_Height (img_descrp));
         matb       : constant Matrix_Access :=
           new Matrix_Type
                 (1 .. GID.Pixel_Width (img_descrp),
                  1 .. GID.Pixel_Height (img_descrp));
         matgrey    : constant Matrix_Access :=
           new Matrix_Type
                 (1 .. GID.Pixel_Width (img_descrp),
                  1 .. GID.Pixel_Height (img_descrp));
         tempString : String (1 .. 3);
      begin
         Put_Line ("IMGBUF " & img_buf'First'Img);
         while x <= img_buf'Last loop
            matr (c, l) := Color_Type (img_buf (x));
            rouge := Color_Type (img_buf (x));
            --  (Standard_Error, 'r');
            x := x + 1;
            if x <= img_buf'Last then
               matg (c, l) := Color_Type (img_buf (x));
               vert := Color_Type (img_buf (x));
               --  Put (Standard_Error, 'b');
               x := x + 1;
               if x <= img_buf'Last then
                  matb (c, l) := Color_Type (img_buf (x));
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
            matgrey (c, l) := grey;

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
         Calculate_Facets (matgrey, Settings);

         if Settings.save_pgm then
            Dump_PGM
              (Ada.Strings.Unbounded.To_String (Settings.outfilename),
               img_descrp,
               matgrey);
         end if;

      end;

      --  printBuffer(i);
      Close (F);
   end PreProcess_Image;

   Settings : Settings_Record;
begin
   if Argument_Count < 1 then
      Help;
      return;
   end if;

   loop
      case Getopt
             ("h -help v -version f: -filter= b -save-binary a -save-ascii"
              & " p -save-pgm o: -output-name= H: --height= c: -config=")
      is
         when 'h'    =>
            Put_Line ("Get help");
            Help;
            return;

         when 'v'    =>
            Version;
            return;

         when 'b'    =>
            Put_Line ("Save stl-bin");
            Settings.save_as_binary := True;

         when 'a'    =>
            Put_Line ("Save stl-acii");
            Settings.save_as_ascii := True;

         when 'p'    =>
            Settings.save_pgm := True;

         when 'o'    =>
            Settings.outfilename :=
              Ada.Strings.Unbounded.To_Unbounded_String (Parameter);

         when 'H'    =>
            Put_Line ("Height");
            Settings.height := Natural'Value (Parameter);

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
               Settings.filter := Lithophane.Filters_Choice'Value (Parameter);
            elsif Full_Switch = "-save-binary" then
               Put_Line ("Seen --save-binary");
               Settings.save_as_binary := True;
            elsif Full_Switch = "-save-ascii" then
               Put_Line ("Seen --save-ascii");
               Settings.save_as_ascii := True;
            elsif Full_Switch = "-height" then
               Settings.height := Natural'Value (Parameter);
               Put_Line ("Seen --height with arg=" & Settings.height'Img);
            elsif Full_Switch = "-output-name" then
               Settings.outfilename :=
                 Ada.Strings.Unbounded.To_Unbounded_String (Parameter);
            elsif Full_Switch = "-save-pgm" then
               Settings.save_pgm := True;
            elsif Full_Switch = "-config" then
               Settings.config :=
                 Ada.Strings.Unbounded.To_Unbounded_String (Parameter);
               Parse_Config (Settings);
            end if;

         when others =>
            exit;
      end case;
   end loop;
   Settings.filename :=
     Ada.Strings.Unbounded.To_Unbounded_String (Get_Argument);

   PreProcess_Image (Settings);

end Lithophane_Main;
