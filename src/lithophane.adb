with TOML;
with TOML.File_IO;

package body Lithophane is

   procedure Print_Matrix
     (the_matrix : Matrix_Access; F : Ada.Text_IO.File_Type := Standard_Output)
   is
   begin
      for i in the_matrix.all'Range (1) loop
         for j in the_matrix.all'Range (2) loop
            Put (F, the_matrix (i, j)'Img & " ");
         end loop;
         New_Line (F);
      end loop;
   end Print_Matrix;

   procedure Parse_Config (Settings : in out Settings_Record) is
      use Ada.Strings.Unbounded;
      use type TOML.Any_Value_Kind;
      use type TOML.Any_Integer;

      Config_Name : constant String := To_String (Settings.config);
      Result      : constant TOML.Read_Result :=
        TOML.File_IO.Load_File (Config_Name);

      Table : TOML.TOML_Value;

      --  Return the entry for Key if it is present and has the Expected kind,
      --  and No_TOML_Value otherwise.
      function Field
        (Key : String; Expected : TOML.Any_Value_Kind) return TOML.TOML_Value
      is
      begin
         if Table.Has (Key) and then Table.Get (Key).Kind = Expected then
            return Table.Get (Key);
         else
            return TOML.No_TOML_Value;
         end if;
      end Field;

   begin
      if not Result.Success then
         Put_Line
           (Standard_Error,
            "error while loading config file " & Config_Name & ":");
         Put_Line (Standard_Error, TOML.Format_Error (Result));
         return;
      end if;

      Table := Result.Value;

      if Table.Kind /= TOML.TOML_Table then
         Put_Line
           (Standard_Error,
            "invalid config file " & Config_Name
            & ": top-level value must be a table");
         return;
      end if;

      declare
         V : TOML.TOML_Value;
      begin
         V := Field ("input-name", TOML.TOML_String);
         if V.Is_Present then
            Settings.filename := TOML.As_Unbounded_String (V);
         end if;

         V := Field ("output-name", TOML.TOML_String);
         if V.Is_Present then
            Settings.outfilename := TOML.As_Unbounded_String (V);
         end if;

         V := Field ("height", TOML.TOML_Integer);
         if V.Is_Present and then TOML.As_Integer (V) >= 0 then
            Settings.height := Natural (TOML.As_Integer (V));
         end if;

         V := Field ("save-binary", TOML.TOML_Boolean);
         if V.Is_Present then
            Settings.save_as_binary := TOML.As_Boolean (V);
         end if;

         V := Field ("save-ascii", TOML.TOML_Boolean);
         if V.Is_Present then
            Settings.save_as_ascii := TOML.As_Boolean (V);
         end if;

         V := Field ("save-pgm", TOML.TOML_Boolean);
         if V.Is_Present then
            Settings.save_pgm := TOML.As_Boolean (V);
         end if;
      end;

      --  The "filter" key is accepted but ignored for now: Settings_Record
      --  has no filter field wired up yet (see TODO in the README).

      Put_Line (Config_Name & " loaded with success!");
   end Parse_Config;

end Lithophane;
