with Ada.Strings.Fixed;

with GNAT.OS_Lib;

package body Lithophane.Interaction is

   procedure Write_Colour_Choice (Settings : in out Settings_Record);
   procedure Write_Filter_Choice (Settings : in out Settings_Record);
   procedure Write_Border_Choice (Settings : in out Settings_Record);
   procedure Write_Output_Choice (Settings : in out Settings_Record);
   procedure Write_Input_Choice (Settings : in out Settings_Record);
   procedure Write_Threshold_Choice (Settings : in out Settings_Record);
   procedure Write_Dimensions_Choice (Settings : in out Settings_Record);
   procedure Write_Custom_Dimensions_Choice
     (Settings : in out Settings_Record);
   procedure Write_Imperial_Standard_Size_Choice
     (Settings : in out Settings_Record);
   procedure Write_Metric_Standard_Size_Choice
     (Settings : in out Settings_Record);
   procedure Write_Filetype_Choice (Settings : in out Settings_Record);
   procedure Write_Resolution_Choice (Settings : in out Settings_Record);

   --  Item without the backslashes that escape its characters: each one is
   --  dropped and the character after it kept as it is. A backslash that
   --  ends Item is kept.
   function Unescaped (Item : String) return String is
      Result  : String (1 .. Item'Length);
      Last    : Natural := 0;
      Escaped : Boolean := False;
   begin
      for I in Item'Range loop
         if Item (I) = '\' and then not Escaped and then I < Item'Last then
            Escaped := True;
         else
            Last := Last + 1;
            Result (Last) := Item (I);
            Escaped := False;
         end if;
      end loop;
      return Result (1 .. Last);
   end Unescaped;

   --  A file name as typed, without the blanks around it nor what a
   --  terminal adds to a file dropped on it: a pair of quotes around the
   --  name ('my picture.png') or a backslash before some of its characters
   --  (my\ picture.png). Backslashes are left alone inside quotes, and
   --  where they separate directories (Windows).
   function Unquoted (Item : String) return String is
      Name : constant String :=
        Ada.Strings.Fixed.Trim (Item, Ada.Strings.Both);
   begin
      if Name'Length >= 2
        and then Name (Name'First) in ''' | '"'
        and then Name (Name'Last) = Name (Name'First)
      then
         return Name (Name'First + 1 .. Name'Last - 1);
      elsif GNAT.OS_Lib.Directory_Separator /= '\' then
         return Unescaped (Name);
      else
         return Name;
      end if;
   end Unquoted;

   procedure Write_Input_Choice (Settings : in out Settings_Record) is
   begin
      Put_Line ("Input file: ");
      declare
         data : constant String := Unquoted (Get_Line);
      begin
         Settings.filename := Ada.Strings.Unbounded.To_Unbounded_String (data);
         Write_Threshold_Choice (Settings);
      end;
   end Write_Input_Choice;

   procedure Write_Colour_Choice (Settings : in out Settings_Record) is
   begin
      Put_Line ("Choose colour mode:");
      Put_Line ("  1 = Black & White (default)");
      Put_Line ("  2 = Colour");
      New_Line;
      Put_Line ("  0 = Exit program");
      declare
         data   : constant String := Get_Line;
         answer : Natural := 1;
      begin
         if data /= "" then
            answer := Natural'Value (data);
         end if;
         case answer is
            when 1      =>
               --  black and white
               Settings.colour := False;
               Write_Filetype_Choice (Settings);

            when 2      =>
               Settings.colour := True;
               Write_Dimensions_Choice (Settings);

            when 0      =>
               raise Interaction_Cancelled;

            when others =>
               raise Constraint_Error;
         end case;
      end;
   end Write_Colour_Choice;

   procedure Write_Filter_Choice (Settings : in out Settings_Record) is
   begin
      Put_Line ("Choose filter:");
      Put_Line ("  1 = Bartlett");
      Put_Line ("  2 = Gauss");
      Put_Line ("  3 = Square");
      Put_Line ("  4 = Sharpen");
      Put_Line ("  5 = None (default)");
      New_Line;
      Put_Line ("  0 = Exit program");
      declare
         data   : constant String := Get_Line;
         answer : Natural := 5;
      begin
         if data /= "" then
            answer := Natural'Value (data);
         end if;
         case answer is
            when 1      =>
               Settings.filter := bartlett;

            when 2      =>
               Settings.filter := gauss;

            when 3      =>
               Settings.filter := square;

            when 4      =>
               Settings.filter := sharpen;

            when 5      =>
               Settings.filter := none;

            when 0      =>
               raise Interaction_Cancelled;

            when others =>
               raise Constraint_Error;
         end case;
         if Settings.filter /= none then
            Put_Line ("Choose filter size (odd number, 3 or more):");
            declare
               data : constant Positive := Positive'Value (Get_Line);
            begin
               if data < 3 or else data mod 2 = 0 then
                  raise Constraint_Error;
               end if;
               Settings.filter_size := data;
            end;
         end if;
         Write_Border_Choice (Settings);
      end;
   end Write_Filter_Choice;

   procedure Write_Border_Choice (Settings : in out Settings_Record) is
   begin
      Put_Line ("Choose border size in pixels:");
      declare
         data : constant Natural := Natural'Value (Get_Line);
      begin
         Settings.border := data;
      end;
      Write_Colour_Choice (Settings);
   end Write_Border_Choice;

   procedure Write_Output_Choice (Settings : in out Settings_Record) is
   begin
      Put_Line
        ("Output filename (default "
         & Ada.Strings.Unbounded.To_String (Settings.outfilename)
         & "): ");
      declare
         data : constant String := Unquoted (Get_Line);
      begin
         if data /= "" then
            Settings.outfilename :=
              Ada.Strings.Unbounded.To_Unbounded_String (data);
         end if;
      end;
   end Write_Output_Choice;

   procedure Write_Threshold_Choice (Settings : in out Settings_Record) is
   begin
      Put_Line ("Put threshold (0.0..1.0):");
      --  The handler covers this answer only, not the questions that
      --  follow.
      begin
         Settings.filter_threshold := Grey_Type'Value (Get_Line);
      exception
         when Constraint_Error =>
            raise Interaction_Error with "invalid threshold";
      end;
      Write_Filter_Choice (Settings);
   end Write_Threshold_Choice;

   procedure Write_Dimensions_Choice (Settings : in out Settings_Record) is
   begin
      Put_Line ("Choose dimension type:");
      Put_Line ("  1 = Metric standard sizes");
      Put_Line ("  2 = Imperial standard sizes");
      Put_Line ("  3 = Custom dimensions");
      New_Line;
      Put_Line ("  0 = Exit program");
      declare
         data   : constant String := Get_Line;
         answer : Natural := 1;
      begin
         if data /= "" then
            answer := Natural'Value (data);
         end if;
         Settings.dimensions.depth := 1.5;
         case answer is
            when 1      =>
               Write_Metric_Standard_Size_Choice (Settings);

            when 2      =>
               Write_Imperial_Standard_Size_Choice (Settings);

            when 3      =>
               Write_Custom_Dimensions_Choice (Settings);

            when 0      =>
               raise Interaction_Cancelled;

            when others =>
               raise Constraint_Error;
         end case;
         Write_Resolution_Choice (Settings);
      end;
   end Write_Dimensions_Choice;

   procedure Write_Custom_Dimensions_Choice (Settings : in out Settings_Record)
   is
   begin
      Put_Line ("Put width in mm:");
      declare
         data : constant Float := Float'Value (Get_Line);
      begin
         Settings.dimensions.width := data;
      end;

      Put_Line ("Put height in mm:");
      declare
         data : constant Float := Float'Value (Get_Line);
      begin
         Settings.dimensions.height := data;
      end;

      Put_Line ("Put depth in mm:");
      declare
         data : constant Float := Float'Value (Get_Line);
      begin
         Settings.dimensions.depth := data;
      end;

   end Write_Custom_Dimensions_Choice;

   procedure Write_Imperial_Standard_Size_Choice
     (Settings : in out Settings_Record) is
   begin
      Put_Line ("Choose size:");
      Put_Line ("  1 = 3.5 x 5 inch");
      Put_Line ("  2 = 4 x 6 inch (default)");
      Put_Line ("  3 = 5 x 7 inch");
      Put_Line ("  4 = 8 x 10 inch");
      New_Line;
      Put_Line ("  0 = Exit program");
      declare
         data   : constant String := Get_Line;
         answer : Natural := 2;
      begin
         if data /= "" then
            answer := Natural'Value (data);
         end if;
         Settings.dimensions.depth := 1.5;
         case answer is
            when 1      =>
               --  3.5 x 5 inch = 89 x 127 mm
               Settings.dimensions.width := 89.0;
               Settings.dimensions.height := 127.0;

            when 2      =>
               --  4 x 6 inch = 102 x 152 mm
               Settings.dimensions.width := 102.0;
               Settings.dimensions.height := 152.0;

            when 3      =>
               --  5 x 7 inch = 127 x 178 mm
               Settings.dimensions.width := 127.0;
               Settings.dimensions.height := 178.0;

            when 4      =>
               --  8 x 10 inch = 203 x 254 mm
               Settings.dimensions.width := 203.0;
               Settings.dimensions.height := 254.0;

            when 0      =>
               raise Interaction_Cancelled;

            when others =>
               raise Constraint_Error;
         end case;

      end;
   end Write_Imperial_Standard_Size_Choice;

   procedure Write_Metric_Standard_Size_Choice
     (Settings : in out Settings_Record) is
   begin
      Put_Line ("Choose size:");
      Put_Line ("  1 =  90 x 130 mm");
      Put_Line ("  2 = 100 x 150 mm (default)");
      Put_Line ("  3 = 130 x 180 mm");
      Put_Line ("  4 = 150 x 200 mm");
      New_Line;
      Put_Line ("  0 = Exit program");
      declare
         data   : constant String := Get_Line;
         answer : Natural := 2;
      begin
         if data /= "" then
            answer := Natural'Value (data);
         end if;
         Settings.dimensions.depth := 1.5;
         case answer is
            when 1      =>
               Settings.dimensions.width := 90.0;
               Settings.dimensions.height := 130.0;

            when 2      =>
               Settings.dimensions.width := 100.0;
               Settings.dimensions.height := 150.0;

            when 3      =>
               Settings.dimensions.width := 130.0;
               Settings.dimensions.height := 180.0;

            when 4      =>
               Settings.dimensions.width := 150.0;
               Settings.dimensions.height := 200.0;

            when 0      =>
               raise Interaction_Cancelled;

            when others =>
               raise Constraint_Error;
         end case;

      end;
   end Write_Metric_Standard_Size_Choice;

   procedure Write_Filetype_Choice (Settings : in out Settings_Record) is
   begin
      Put_Line ("Choose file type:");
      Put_Line ("  1 = STL binary");
      Put_Line ("  2 = STL ascii");
      Put_Line ("  3 = 3MF (default)");
      New_Line;
      Put_Line ("  0 = Exit program");
      declare
         data   : constant String := Get_Line;
         answer : Natural := 3;
      begin
         if data /= "" then
            answer := Natural'Value (data);
         end if;
         Settings.dimensions.depth := 1.5;
         case answer is
            when 1      =>
               Settings.save_as_binary := True;
               Settings.save_as_ascii := False;
               Settings.save_as_3mf := False;
               Write_Resolution_Choice (Settings);

            when 2      =>
               Settings.save_as_binary := False;
               Settings.save_as_ascii := True;
               Settings.save_as_3mf := False;
               Write_Resolution_Choice (Settings);

            when 3      =>
               Settings.save_as_binary := False;
               Settings.save_as_ascii := False;
               Settings.save_as_3mf := True;
               Write_Dimensions_Choice (Settings);

            when 0      =>
               raise Interaction_Cancelled;

            when others =>
               raise Constraint_Error;
         end case;
      end;
   end Write_Filetype_Choice;

   procedure Write_Resolution_Choice (Settings : in out Settings_Record) is
   begin
      Put_Line
        ("Choose maximum image dimension (default 1500 pixels,"
         & " 0 = no limit) :");
      declare
         data   : constant String := Get_Line;
         answer : Natural := 1_500;
      begin
         if data /= "" then
            answer := Natural'Value (data);
         end if;
         Settings.max_size := answer;
         Write_Output_Choice (Settings);
      end;
   end Write_Resolution_Choice;

   procedure Show_Interaction (Settings : in out Settings_Record) is
   begin
      Write_Input_Choice (Settings);
   exception
      when Constraint_Error =>
         raise Interaction_Error with "invalid answer";
      when End_Error =>
         raise Interaction_Error
           with "standard input ended before all the questions were answered";
   end Show_Interaction;

end Lithophane.Interaction;
