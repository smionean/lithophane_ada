------------------------------------------------------------------------------
--  lithophane-commandline.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Command line parser built on AdaCL.Command_Line.GetOpt. Every option has
--  a short form (-H 5, -H5) and a GNU long form; the value of a long option
--  may be attached with '=' (--height=5) or given as the next argument
--  (--height 5). The positional arguments are the input image and, right
--  after a filter name, the optional filter size.
--
--  A value that cannot be decoded raises Option_Parse_Error, and an invalid
--  combination raises Option_Wrong_Error (both declared in
--  AdaCL.Command_Line.GetOpt), with a human-readable message.
------------------------------------------------------------------------------

pragma Ada_2022;

with Ada.Command_Line;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Wide_Wide_Text_IO;

with Lithophane_Config;

package body Lithophane.Commandline is

   package SU renames Ada.Strings.Unbounded;
   package WWIO renames Ada.Wide_Wide_Text_IO;

   --  The options that carry a value, whatever their spelling.
   type Valued_Option is
     (Opt_Border,
      Opt_Height,
      Opt_Filter,
      Opt_Threshold,
      Opt_Dimensions,
      Opt_Max_Size,
      Opt_Outfilename,
      Opt_Config,
      Opt_None);

   Pattern : constant Wide_Wide_String :=
     Inherited.Help_Short
     & Help_Short
     & Version_Short
     & Save_As_STL_Binary_Short
     & Save_As_STL_ASCII_Short
     & Save_As_3MF_Short
     & Save_PGM_Short
     & Colour_Short
     & Border_Short
     & Inherited.Option_Argument
     & Height_Short
     & Inherited.Option_Argument
     & Filter_Short
     & Inherited.Option_Argument
     & Filter_Threshold_Short
     & Inherited.Option_Argument
     & Dimensions_Short
     & Inherited.Option_Argument
     & Max_Size_Short
     & Inherited.Option_Argument
     & Outfilename_Short
     & Inherited.Option_Argument
     & Config_Short
     & Inherited.Option_Argument
     & Interaction_Short;

   --  Long options handled by AdaCL.Trace itself start with this prefix.
   Trace_Prefix : constant Wide_Wide_String := "TRACE";

   Long_Marker : constant Wide_Wide_String := "--";

   function To_UTF_8 (Item : Wide_Wide_String) return String
   is (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode (Item));

   function To_Wide (Item : String) return Wide_Wide_String
   is (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Item));

   function Starts_With (Item, Prefix : Wide_Wide_String) return Boolean
   is (Item'Length >= Prefix'Length
       and then Item (Item'First .. Item'First + Prefix'Length - 1) = Prefix);

   function All_Digits (Item : Wide_Wide_String) return Boolean
   is (Item'Length > 0 and then (for all C of Item => C in '0' .. '9'));

   --  The command line argument at Index, or "" when there is none.
   function Token (Index : Integer) return Wide_Wide_String
   is (if Index in 1 .. Ada.Command_Line.Argument_Count
       then To_Wide (Ada.Command_Line.Argument (Index))
       else "");

   procedure Invalid (Message : String)
   with No_Return;

   procedure Invalid (Message : String) is
   begin
      raise Inherited.Option_Parse_Error with Message;
   end Invalid;

   function To_Valued (Short : Wide_Wide_Character) return Valued_Option
   is (if Short = Border_Short
       then Opt_Border
       elsif Short = Height_Short
       then Opt_Height
       elsif Short = Filter_Short
       then Opt_Filter
       elsif Short = Filter_Threshold_Short
       then Opt_Threshold
       elsif Short = Dimensions_Short
       then Opt_Dimensions
       elsif Short = Max_Size_Short
       then Opt_Max_Size
       elsif Short = Outfilename_Short
       then Opt_Outfilename
       elsif Short = Config_Short
       then Opt_Config
       else Opt_None);

   function To_Valued (Long : Wide_Wide_String) return Valued_Option
   is (if Long = Border_Long
       then Opt_Border
       elsif Long = Height_Long
       then Opt_Height
       elsif Long = Filter_Long
       then Opt_Filter
       elsif Long = Filter_Threshold_Long
       then Opt_Threshold
       elsif Long = Dimensions_Long
       then Opt_Dimensions
       elsif Long = Max_Size_Long
       then Opt_Max_Size
       elsif Long = Outfilename_Long
       then Opt_Outfilename
       elsif Long = Config_Long
       then Opt_Config
       else Opt_None);

   --  Decode a "WxHxD" value (millimetres). A component left empty is 0.0,
   --  which leaves that axis unconstrained.
   function To_Dimensions (Spec : String) return Dimensions_Type is
      Result : Dimensions_Type;
      Start  : Positive := Spec'First;
      Axis   : Natural := 0;

      procedure Take (S : String) is
         Val : Float := 0.0;
      begin
         if S /= "" then
            Val := Float'Value (S);
            if Val < 0.0 then
               raise Constraint_Error;
            end if;
         end if;
         case Axis is
            when 0      =>
               Result.width := Val;

            when 1      =>
               Result.height := Val;

            when 2      =>
               Result.depth := Val;

            when others =>
               raise Constraint_Error;
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
      return Result;
   exception
      when Constraint_Error =>
         Invalid
           ("invalid dimensions """
            & Spec
            & """; expected <W>x<H>x<D> in millimetres, e.g. 100x100x1.5");
   end To_Dimensions;

   function Is_Help_Requested (This : Object) return Boolean
   is (This.Help_Requested);

   function Is_Version_Requested (This : Object) return Boolean
   is (This.Version_Requested);

   function Is_Interactive (This : Object) return Boolean
   is (This.Interaction);

   function To_Settings (This : Object) return Settings_Record
   is (border           => This.Border,
       height           => This.Height,
       height_is_set    => This.Height_Is_Set,
       filter           => This.Filter,
       filter_size      => This.Filter_Size,
       filter_threshold => This.Filter_Threshold,
       save_as_binary   => This.Save_As_Binary,
       save_as_ascii    => This.Save_As_ASCII,
       save_as_3mf      => This.Save_As_3MF,
       save_pgm         => This.Save_PGM,
       colour           => This.Colour,
       dimensions       => This.Dimensions,
       max_size         => This.Max_Size,
       filename         => This.Filename,
       outfilename      => This.Outfilename,
       config           => This.Config);

   --  Read the TOML file named by This.Config and override the matching
   --  options, input file included, with the values it contains.
   procedure Apply_Config (This : in out Object) is
      Settings : Settings_Record := This.To_Settings;
   begin
      Parse_Config (Settings);

      This.Border := Settings.border;
      This.Height := Settings.height;
      This.Height_Is_Set := Settings.height_is_set;
      This.Filter := Settings.filter;
      This.Filter_Size := Settings.filter_size;
      This.Filter_Threshold := Settings.filter_threshold;
      This.Save_As_Binary := Settings.save_as_binary;
      This.Save_As_ASCII := Settings.save_as_ascii;
      This.Save_As_3MF := Settings.save_as_3mf;
      This.Save_PGM := Settings.save_pgm;
      This.Colour := Settings.colour;
      This.Dimensions := Settings.dimensions;
      This.Max_Size := Settings.max_size;
      This.Filename := Settings.filename;
      This.Outfilename := Settings.outfilename;
   exception
      when Constraint_Error =>
         Invalid
           ("invalid value in config file """
            & SU.To_String (Settings.config)
            & """");
   end Apply_Config;

   --  Store the value given to a valued option, rejecting anything that
   --  cannot be decoded.
   procedure Apply
     (This : in out Object; Option : Valued_Option; Value : Wide_Wide_String)
   is
      Spec : constant String := To_UTF_8 (Value);
   begin
      case Option is
         when Opt_Border      =>
            begin
               This.Border := Natural'Value (Spec);
            exception
               when Constraint_Error =>
                  Invalid
                    ("invalid border value """
                     & Spec
                     & """; expected a non-negative integer");
            end;

         when Opt_Height      =>
            begin
               This.Height := Float'Value (Spec);
               if This.Height <= 0.0 then
                  raise Constraint_Error;
               end if;
               This.Height_Is_Set := True;
            exception
               when Constraint_Error =>
                  Invalid
                    ("invalid height value """
                     & Spec
                     & """; expected a positive number");
            end;

         when Opt_Filter      =>
            begin
               This.Filter := Filters_Choice'Value (Spec);
            exception
               when Constraint_Error =>
                  Invalid
                    ("unknown filter """
                     & Spec
                     & """; expected one of bartlett, gauss, square,"
                     & " sharpen, none");
            end;

         when Opt_Threshold   =>
            begin
               This.Filter_Threshold := Grey_Type'Value (Spec);
            exception
               when Constraint_Error =>
                  Invalid
                    ("invalid threshold value """
                     & Spec
                     & """; expected a number between 0.0 and 1.0");
            end;

         when Opt_Dimensions  =>
            This.Dimensions := To_Dimensions (Spec);

         when Opt_Max_Size    =>
            begin
               This.Max_Size := Natural'Value (Spec);
            exception
               when Constraint_Error =>
                  Invalid
                    ("invalid max-size value """
                     & Spec
                     & """; expected a non-negative integer");
            end;

         when Opt_Outfilename =>
            This.Outfilename := SU.To_Unbounded_String (Spec);

         when Opt_Config      =>
            --  Read once the whole command line is known: see Parse.
            This.Config := SU.To_Unbounded_String (Spec);

         when Opt_None        =>
            null;
      end case;
   end Apply;

   --  Put the scanner back at the start of the command line argument
   --  Target. AdaCL 8.0.0 leaves its cluster index past the letter of an
   --  option whose value is stuck to it (-H5), so the next short option
   --  would be read one character too far. That index is private to GetOpt:
   --  the only way to reset it is to restart the scanner and skip, with a
   --  pattern that knows no valued option, the arguments already handled.
   procedure Rewind (This : in out Object; Target : Positive) is
      Fresh : Inherited.Object;
      Found : Inherited.Found_Flag;
   begin
      Inherited.Object (This) := Fresh;
      This.Set_Pattern ([Inherited.Option_Error]);
      while This.Get_Option_Index < Target loop
         This.Next (Found);
      end loop;

      This.Set_Pattern (Pattern);
      This.Set_Extract_GNU;
      This.Set_Exception_On_Error;
   end Rewind;

   overriding
   procedure Parse (This : in out Object) is
      This_C : Object'Class renames Object'Class (This);
      Found  : Inherited.Found_Flag;
      Index  : Positive;
   begin
      This.Set_Pattern (Pattern);
      This.Set_Extract_GNU;
      This.Set_Exception_On_Error;

      --  The inherited Parse silently skips the tokens Next reports as
      --  Error (an unknown short option), hence this dispatch loop.
      loop
         Index := This.Get_Option_Index;
         begin
            This.Next (Found);
         exception
            when Inherited.Option_Parse_Error =>
               --  The value of the last short option is missing.
               Invalid
                 ("missing parameter for switch: "
                  & To_UTF_8 (Token (Ada.Command_Line.Argument_Count)));
         end;

         case Found is
            when Inherited.End_Of_Options   =>
               exit;

            when Inherited.With_Argument    =>
               This_C.Analyze_With_Argument;
               Rewind (This, This.Get_Option_Index);

            when Inherited.Without_Argument =>
               This_C.Analyze_Without_Argument;

            when Inherited.GNU_Style        =>
               This_C.Analyze_GNU;

            when Inherited.No_Option        =>
               This_C.Analyze_File;

            when Inherited.Error            =>
               Invalid
                 ("invalid command line switch: " & To_UTF_8 (Token (Index)));
         end case;

         exit when This.Help_Requested or else This.Version_Requested;
      end loop;

      --  The config file has the last word, wherever -c stands on the
      --  command line.
      if not This.Help_Requested
        and then not This.Version_Requested
        and then SU.Length (This.Config) > 0
      then
         Apply_Config (This);
      end if;
   end Parse;

   overriding
   procedure Write_Help (This : Object) is
      use Inherited;
   begin
      WWIO.Put_Line
        ("Lithophane " & To_Wide (Lithophane_Config.Crate_Version));
      WWIO.Put_Line ("Usage: lithophane [options] <input_file>");
      WWIO.Put_Line ("Options:");
      Put_Help_Line (Help_Short, Help_Long, "this help");
      Put_Help_Line (Version_Short, Version_Long, "print the version");
      Put_Help_Line
        (Save_As_STL_Binary_Short,
         Save_As_STL_Binary_Long,
         "write <name>.bin.stl (default)");
      Put_Help_Line
        (Save_As_STL_ASCII_Short,
         Save_As_STL_ASCII_Long,
         "write <name>.ascii.stl");
      Put_Help_Line (Save_As_3MF_Short, Save_As_3MF_Long, "write <name>.3mf");
      Put_Help_Line
        (Save_PGM_Short,
         Save_PGM_Long,
         "write the greyscale image as <name>.pgm");
      Put_Help_Line
        (Colour_Short,
         Colour_Long,
         "write a colour lithophane (cyan, magenta, yellow and white"
         & " parts) as <name>.3mf; no STL is written");
      Put_Help_Line
        (Outfilename_Short,
         Outfilename_Long,
         "name",
         "base name of the output files (default test)");
      Put_Help_Line
        (Height_Short,
         Height_Long,
         "mm",
         "maximum relief height (positive number, default 10.0)");
      Put_Help_Line
        (Border_Short,
         Border_Long,
         "pixels",
         "width of the border around the image (default 20)");
      Put_Help_Line
        (Dimensions_Short,
         Dimensions_Long,
         "WxHxD",
         "target 3MF size in mm; an empty or 0 W or H keeps the aspect"
         & " ratio, a non-zero D overrides --height");
      Put_Help_Line
        (Filter_Short,
         Filter_Long,
         "name",
         "bartlett, gauss, square, sharpen or none; an odd number right"
         & " after it is the filter size (default 3)");
      Put_Help_Line
        (Filter_Threshold_Short,
         Filter_Threshold_Long,
         "n",
         "grey level 0.0 .. 1.0 (default 0.5) below which pixels are cut"
         & " to 0.0");
      Put_Help_Line
        (Max_Size_Short,
         Max_Size_Long,
         "pixels",
         "maximum image dimension (default 1500, 0 = no limit)");
      Put_Help_Line
        (Config_Short,
         Config_Long,
         "file",
         "read options from a TOML file; it overrides the command line");
      Put_Help_Line
        (Interaction_Short,
         Interaction_Long,
         "ask for the settings one by one instead of reading them from"
         & " the command line; the other options are ignored");
      New_Line;
   end Write_Help;

   overriding
   procedure Analyze_Without_Argument (This : in out Object) is
      Option : constant Wide_Wide_Character := This.Get_Option;
   begin
      if Option = Help_Short then
         Object'Class (This).Write_Help;
         This.Help_Requested := True;
      elsif Option = Version_Short then
         This.Version_Requested := True;
      elsif Option = Save_As_STL_Binary_Short then
         This.Save_As_Binary := True;
      elsif Option = Save_As_STL_ASCII_Short then
         This.Save_As_ASCII := True;
      elsif Option = Save_As_3MF_Short then
         This.Save_As_3MF := True;
      elsif Option = Save_PGM_Short then
         This.Save_PGM := True;
      elsif Option = Colour_Short then
         This.Colour := True;
      elsif Option = Interaction_Short then
         This.Interaction := True;
      else
         --  -? is the help switch built in AdaCL.
         Inherited.Analyze_Without_Argument (Inherited.Object (This));
         This.Help_Requested := This.Help_Shown;
      end if;
   end Analyze_Without_Argument;

   overriding
   procedure Analyze_With_Argument (This : in out Object) is
      Option : constant Valued_Option := To_Valued (This.Get_Option);
   begin
      if Option = Opt_None then
         Inherited.Analyze_With_Argument (Inherited.Object (This));
      else
         Apply (This, Option, This.Get_Argument);
      end if;
   end Analyze_With_Argument;

   overriding
   procedure Analyze_GNU (This : in out Object) is
      Name   : constant Wide_Wide_String := This.Get_GNU_Option;
      Value  : constant Wide_Wide_String := This.Get_Argument;
      Option : constant Valued_Option := To_Valued (Name);
      --  Next has already moved past the option itself.
      Self   : constant Wide_Wide_String := Token (This.Get_Option_Index - 1);
      Next   : constant Wide_Wide_String := Token (This.Get_Option_Index);
   begin
      if Option /= Opt_None then
         if Value /= "" then
            Apply (This, Option, Value);
         elsif Self /= Long_Marker & Name
           or else Next = ""
           or else Starts_With (Next, "-")
         then
            Invalid ("missing parameter for switch: --" & To_UTF_8 (Name));
         end if;
      --  Otherwise the value is the next argument: Analyze_File
      --  picks it up.

      elsif Value /= "" and then not Starts_With (Name, Trace_Prefix) then
         Invalid
           ("invalid command line switch: --"
            & To_UTF_8 (Name)
            & " (it takes no parameter)");
      elsif Name = Help_Long then
         Inherited.Analyze_GNU (Inherited.Object (This));
         This.Help_Requested := True;
      elsif Name = Version_Long then
         This.Version_Requested := True;
      elsif Name in Save_As_STL_Binary_Long | Save_As_STL_Binary_Legacy_Long
      then
         This.Save_As_Binary := True;
      elsif Name in Save_As_STL_ASCII_Long | Save_As_STL_ASCII_Legacy_Long then
         This.Save_As_ASCII := True;
      elsif Name = Save_As_3MF_Long then
         This.Save_As_3MF := True;
      elsif Name = Save_PGM_Long then
         This.Save_PGM := True;
      elsif Name = Colour_Long then
         This.Colour := True;
      elsif Name = Interaction_Long then
         This.Interaction := True;
      elsif Starts_With (Name, Trace_Prefix) then
         Inherited.Analyze_GNU (Inherited.Object (This));
      else
         Invalid ("invalid command line switch: --" & To_UTF_8 (Name));
      end if;
   end Analyze_GNU;

   overriding
   procedure Analyze_File (This : in out Object) is
      Value    : constant Wide_Wide_String := This.Get_Argument;
      --  Next has already moved past Value, so the argument that came
      --  before it is two steps back.
      Previous : constant Wide_Wide_String :=
        Token (This.Get_Option_Index - 2);
      Option   : constant Valued_Option :=
        (if Starts_With (Previous, Long_Marker)
         then
           To_Valued
             (Previous (Previous'First + Long_Marker'Length .. Previous'Last))
         else Opt_None);
   begin
      if Option /= Opt_None then
         --  Value of a long option written without '=' (--height 5).
         Apply (This, Option, Value);

      elsif This.Filter /= none
        and then not This.Filename_Given
        and then All_Digits (Value)
      then
         --  The number that follows a filter name is the filter size.
         declare
            Spec : constant String := To_UTF_8 (Value);
         begin
            This.Filter_Size := Natural'Value (Spec);
            if This.Filter_Size < 3 or else This.Filter_Size mod 2 = 0 then
               raise Constraint_Error;
            end if;
         exception
            when Constraint_Error =>
               Invalid
                 ("invalid filter size """
                  & Spec
                  & """; expected an odd number, 3 or more");
         end;

      elsif not This.Filename_Given then
         This.Filename := SU.To_Unbounded_String (To_UTF_8 (Value));
         This.Filename_Given := True;

      else
         raise Inherited.Option_Wrong_Error
           with
             "more than one input image file given: """
             & SU.To_String (This.Filename)
             & """ and """
             & To_UTF_8 (Value)
             & """";
      end if;
   end Analyze_File;

end Lithophane.Commandline;
