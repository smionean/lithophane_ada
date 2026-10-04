pragma Ada_2022;
pragma Extensions_Allowed (On);

with Ada.Strings.Unbounded;
with AdaCL.Command_Line.GetOpt;

package Lithophane.Commandline is

   type Object is new AdaCL.Command_Line.GetOpt.Object with private;

   overriding
   procedure Parse (This : in out Object);

   overriding
   procedure Write_Help (This : Object);

   overriding
   procedure Analyze_Without_Argument (This : in out Object);

   overriding
   procedure Analyze_With_Argument (This : in out Object);

   overriding
   procedure Analyze_GNU (This : in out Object);

   overriding
   procedure Analyze_File (This : in out Object);

   --  True once -h, --help or -? has been seen: the help has been written
   --  and Parse has stopped there.
   function Is_Help_Requested (This : Object) return Boolean;

   --  True once -v or --version has been seen: Parse has stopped there.
   function Is_Version_Requested (This : Object) return Boolean;

   --  The options gathered by Parse, as the record used by the rest of the
   --  program.
   function To_Settings (This : Object) return Settings_Record;

private

   package Inherited renames AdaCL.Command_Line.GetOpt;

   Border_Long  : constant Wide_Wide_String := "border";
   Border_Short : constant Wide_Wide_Character := 'B';

   Height_Long  : constant Wide_Wide_String := "height";
   Height_Short : constant Wide_Wide_Character := 'H';

   Filter_Long  : constant Wide_Wide_String := "filter";
   Filter_Short : constant Wide_Wide_Character := 'f';

   Filter_Threshold_Long  : constant Wide_Wide_String := "threshold";
   Filter_Threshold_Short : constant Wide_Wide_Character := 't';

   Save_As_STL_Binary_Long        : constant Wide_Wide_String :=
     "save-stl-binary";
   Save_As_STL_Binary_Legacy_Long : constant Wide_Wide_String := "save-binary";
   Save_As_STL_Binary_Short       : constant Wide_Wide_Character := 'b';

   Save_As_STL_ASCII_Long        : constant Wide_Wide_String :=
     "save-stl-ascii";
   Save_As_STL_ASCII_Legacy_Long : constant Wide_Wide_String := "save-ascii";
   Save_As_STL_ASCII_Short       : constant Wide_Wide_Character := 'a';

   Save_As_3MF_Long  : constant Wide_Wide_String := "save-3mf";
   Save_As_3MF_Short : constant Wide_Wide_Character := 'm';

   Save_PGM_Long  : constant Wide_Wide_String := "save-pgm";
   Save_PGM_Short : constant Wide_Wide_Character := 'p';

   Dimensions_Long  : constant Wide_Wide_String := "dimensions";
   Dimensions_Short : constant Wide_Wide_Character := 'd';

   Max_Size_Long  : constant Wide_Wide_String := "max-size";
   Max_Size_Short : constant Wide_Wide_Character := 'M';

   Outfilename_Long  : constant Wide_Wide_String := "output-name";
   Outfilename_Short : constant Wide_Wide_Character := 'o';

   Config_Long  : constant Wide_Wide_String := "config";
   Config_Short : constant Wide_Wide_Character := 'c';

   Version_Long  : constant Wide_Wide_String := "version";
   Version_Short : constant Wide_Wide_Character := 'v';

   Help_Long  : constant Wide_Wide_String := "help";
   Help_Short : constant Wide_Wide_Character := 'h';

   type Object is new Inherited.Object with record
      Help_Requested    : Boolean := False;
      Version_Requested : Boolean := False;
      Border            : Natural := 20;
      Height            : Float := 10.0;
      Height_Is_Set     : Boolean := False;
      Filter            : Filters_Choice := none;
      Filter_Size       : Natural := 3;
      Filter_Threshold  : Grey_Type := 0.5;
      Save_As_Binary    : Boolean := True;
      Save_As_ASCII     : Boolean := False;
      Save_As_3MF       : Boolean := False;
      Save_PGM          : Boolean := False;
      Dimensions        : Dimensions_Type := (others => 0.0);
      Max_Size          : Natural :=
        1_500;   --  maximum image dimension (0 = no limit)
      Filename          : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Filename_Given    : Boolean := False;
      --  True once the input file was given on the command line itself: it
      --  then replaces the one a config file may have named.
      Outfilename       : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String ("test");
      Config            : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

end Lithophane.Commandline;
