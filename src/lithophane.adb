package body Lithophane
is

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

   procedure Parse_Config (Settings : Settings_Record) is
   begin
      null;
   end Parse_Config;

end Lithophane;
