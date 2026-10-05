------------------------------------------------------------------------------
--  lithophane_main.adb
--
--  Program entry point. Drives the whole pipeline:
--    * parse the command line (Lithophane.Commandline) and print help/version;
--    * load the input image with GID into a raw 24-bit RGB bitmap;
--    * convert it to a normalised greyscale height map (Grey_Type,
--      1.0 - luminance, so dark pixels become thick; optionally saved as
--      PGM), surrounded by a border of 1.0;
--    * pick and apply the requested filter (bartlett, gauss, square,
--      sharpen), optionally overridden by a TOML config;
--    * always apply the threshold filter (Settings.filter_threshold,
--      0.0 .. 1.0, set with -t/--threshold);
--    * shrink the height map so its larger side fits Settings.max_size;
--    * build the mesh via Lithophane.Calculate_Facets (relief scaled by
--      Settings.height, set with -H/--height) and write it out as
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
with AdaCL.Command_Line.GetOpt;

with Interfaces;

with Lithophane;                 use Lithophane;
with Lithophane.Commandline;
with Lithophane.STL;             use Lithophane.STL;
with Lithophane.File3mf;         use Lithophane.File3mf;
with Lithophane.Filters;         use Lithophane.Filters;
with Lithophane.Image_Utilities; use Lithophane.Image_Utilities;

procedure Lithophane_Main is

   Lithophane_Version : constant String := "1.2.0";

   --
   --  Version
   --
   procedure Version is
   begin
      Put_Line (Standard_Error, "Lithophane " & Lithophane_Version);
   end Version;

   --  Raised once a fatal, user-facing problem has been reported (the
   --  human-readable diagnostic is printed by Fail before the exception is
   --  propagated). The top-level handler turns it into a non-zero exit
   --  status without dumping a raw exception trace on the user.
   Fatal_Error : exception;

   --
   --  Fail
   --   @param Message the human-readable error message to print
   --
   procedure Fail (Message : String) is
   begin
      Put_Line (Standard_Error, "Error: " & Message);
      raise Fatal_Error;
   end Fail;

   --
   --  Close_If_Open
   --   @param F the file to close if it is still open
   --
   --  Close F if it is still open, swallowing any secondary error so the
   --  original problem is the one that reaches the user.
   --
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

   --
   --  Load_Raw_Image
   --   @param image the GID descriptor of the source image
   --   @param buffer the raw 24-bit RGB bitmap to fill
   --   @param next_frame the time until the next frame (for animated GIFs)
   --
   --  Load image into a 24-bit truecolor RGB raw bitmap (for a PPM output)
   --  or into a greyscale matrix (for the lithophane mesh). The bitmap is
   --  allocated here and must be freed by the caller.
   --  The bitmap is a linear array of bytes, three per pixel, in row-major
   --  order, with the first pixel at the top-left corner of the image.
   --
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

   procedure Print_Matrix_PGM
     (the_matrix : Matrix_Grey_Access;
      F          : Ada.Text_IO.File_Type := Standard_Output)
   is
      --  Plain PGM lines should not exceed 70 characters; a sample takes at
      --  most 4 (" 255").
      Samples_Per_Line : constant := 17;
      count            : Natural := 0;
   begin
      --  The matrix is indexed (column, row) with row 1 at the bottom of
      --  the picture (GID's convention), while PGM is written row by row
      --  from the top: the row index is the outer loop, in reverse.
      for j in reverse the_matrix.all'Range (2) loop
         for i in the_matrix.all'Range (1) loop
            --  The conversion to Integer already rounds to nearest.
            Put
              (F, Integer'Image (Integer ((1.0 - the_matrix (i, j)) * 255.0)));
            count := count + 1;
            if count = Samples_Per_Line then
               New_Line (F);
               count := 0;
            end if;
         end loop;
         if count /= 0 then
            New_Line (F);
            count := 0;
         end if;
      end loop;
   end Print_Matrix_PGM;

   procedure Dump_PGM (name : String; the_image : Matrix_Grey_Access) is
      F : Ada.Text_IO.File_Type;
   begin
      Create (F, Out_File, name & ".pgm");
      --  PGM header: width then height, taken from the matrix itself (it
      --  includes the border and may have been resized).
      Put_Line (F, "P2");
      Put_Line
        (F,
         Integer'Image (the_image'Length (1))
         & " "
         & Integer'Image (the_image'Length (2)));
      Put_Line (F, "255");
      Print_Matrix_PGM (the_image, F);
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
   --   @param the_image the greyscale image to filter
   --   @param Settings the settings for the lithophane generation
   --
   procedure Process_Image
     (the_image : Matrix_Grey_Access; Settings : Settings_Record) is
   begin

      --  apply a filter
      case Settings.filter is
         when bartlett =>
            Apply_Filter
              (the_image,
               Create_Bartlett_Filter
                 (Settings.filter_size, Settings.filter_size));

         when gauss    =>
            Apply_Filter
              (the_image,
               Create_Gauss_Filter
                 (Settings.filter_size, Settings.filter_size));

         when square   =>
            Apply_Filter
              (the_image,
               Create_Square_Filter
                 (Settings.filter_size, Settings.filter_size));

         when sharpen  =>
            Apply_Filter
              (the_image,
               Create_Sharpen_Filter
                 (Settings.filter_size, Settings.filter_size));

         when none     =>
            null;

      end case;

   end Process_Image;

   --
   --  Generate_Lithophane
   --   @param the_image the greyscale image to convert into a lithophane
   --   @param Settings the settings for the lithophane generation
   --
   procedure Generate_Lithophane
     (the_image : Matrix_Grey_Access; Settings : Settings_Record)
   is
      Facets_List : Facets.Vector;
   begin
      Process_Image (the_image, Settings);
      Facets_List := Calculate_Facets (the_image, Settings);

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
           (Ada.Strings.Unbounded.To_String (Settings.outfilename), the_image);
      end if;
   end Generate_Lithophane;

   --
   --  Prepare_Lithophane
   --   @param Settings the settings for the lithophane generation
   --
   procedure Prepare_Lithophane (Settings : Settings_Record) is

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
      grey  : Grey_Type := 0.0;
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
         --  Only the greyscale height map is ever read afterwards. The raw
         --  R/G/B planes used to be materialised as three extra full-size
         --  Color_Type matrices; they were written but never used, so for a
         --  large photo they wasted ~3x the height map's memory (which, with
         --  the facet list, is what pushed the 3MF path into Storage_Error).
         matgrey : constant Matrix_Grey_Access :=
           new Matrix_Grey_Type
                 (1 .. GID.Pixel_Width (img_descrp) + 2 * Settings.border,
                  1 .. GID.Pixel_Height (img_descrp) + 2 * Settings.border);
      begin
         Put_Line ("IMGBUF " & img_buf'First'Img);
         for i in matgrey'Range (1) loop
            for j in matgrey'Range (2) loop
               matgrey (i, j) := 1.0;
            end loop;
         end loop;

         while x <= img_buf'Last loop
            rouge := Color_Type (img_buf (x));
            --  (Standard_Error, 'r');
            x := x + 1;
            if x <= img_buf'Last then
               vert := Color_Type (img_buf (x));
               --  Put (Standard_Error, 'b');
               x := x + 1;
               if x <= img_buf'Last then
                  bleu := Color_Type (img_buf (x));
               --  Put (Standard_Error, 'g');

               end if;
            end if;
            grey :=
              Grey_Type
                (1.0
                 - (0.2989 * Float (rouge) + 0.5870 * Float (vert)
                    + 0.1140 * Float (bleu))
                   / 255.0);
            --  Put_Line ("GREY " & grey'Img);
            matgrey (c + Settings.border, l + Settings.border) := grey;
            x := x + 1;
            if c mod GID.Pixel_Width (img_descrp) = 0 then
               c := 1; --  Put(Standard_Error," c=1");
               l := l + 1; --  Put(Standard_Error,"+l");

            else
               c := c + 1; --  Put(Standard_Error," +c");
            end if;

         end loop;

         --  The raw bitmap has been folded into matgrey; release it before
         --  the (much larger) facet list is built.
         Dispose (img_buf);

         Apply_Threshold_Filter (matgrey, Settings.filter_threshold);

         if Settings.max_size /= 0
           and then
             (matgrey'Length (1) > Settings.max_size
              or else matgrey'Length (2) > Settings.max_size)
         then
            Put_Line
              (Standard_Error,
               "Image is large; this may take a while to process..."
               & matgrey'Length (1)'Img);
            declare
               new_width  : constant Natural :=
                 Calculate_New_Image_Size
                   (matgrey'Length (1), matgrey'Length (2), tWIDTH, Settings);
               new_height : constant Natural :=
                 Calculate_New_Image_Size
                   (matgrey'Length (1), matgrey'Length (2), tHEIGHT, Settings);
               resized    : constant Matrix_Grey_Access :=
                 Resize_Image (matgrey, new_width, new_height);
            begin
               Generate_Lithophane (resized, Settings);
            end;
         else
            Generate_Lithophane (matgrey, Settings);
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
           (""""
            & Ada.Strings.Unbounded.To_String (Settings.filename)
            & """ is not in an image format GID recognises");

      when
        GID.known_but_unsupported_image_format
        | GID.unsupported_image_subformat
      =>
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
   end Prepare_Lithophane;

   Options  : Lithophane.Commandline.Object;
   Settings : Settings_Record;

begin
   if Argument_Count < 1 then
      Options.Write_Help;
      return;
   end if;

   Options.Parse;

   if Options.Is_Help_Requested then
      return;
   elsif Options.Is_Version_Requested then
      Version;
      return;
   end if;

   Settings := Options.To_Settings;

   if Ada.Strings.Unbounded.Length (Settings.filename) = 0 then
      Put_Line (Standard_Error, "Error: no input image file given.");
      Put_Line (Standard_Error, "Try 'lithophane --help'.");
      Set_Exit_Status (Failure);
      return;
   end if;

   --  In the 3MF output a requested depth fixes the total thickness, so an
   --  explicit height no longer gives the relief height in millimetres.
   if Settings.save_as_3mf
     and then Settings.height_is_set
     and then Settings.dimensions.depth > 0.0
   then
      Put_Line
        (Standard_Error,
         "Warning: the depth given in --dimensions overrides --height in"
         & " the 3MF output: the total thickness (base + relief) is"
         & Settings.dimensions.depth'Img
         & " mm");
   end if;

   Prepare_Lithophane (Settings);

exception
   when Fatal_Error =>
      --  A human-readable diagnostic has already been printed by Fail.
      Set_Exit_Status (Failure);

   when
     E :
       AdaCL.Command_Line.GetOpt.Option_Parse_Error
       | AdaCL.Command_Line.GetOpt.Option_Wrong_Error
   =>
      Put_Line (Standard_Error, "Error: " & Exception_Message (E));
      Put_Line (Standard_Error, "Try 'lithophane --help'.");
      Set_Exit_Status (Failure);

   when E : Config_Error =>
      Put_Line (Standard_Error, "Error: " & Exception_Message (E));
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
