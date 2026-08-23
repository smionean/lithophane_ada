package Lithophane.STL is

   procedure Dump_STL_ASCII
     (Facets_List : Facets.Vector; Settings : Settings_Record);
   procedure Dump_STL_BIN
     (Facets_List : Facets.Vector; Settings : Settings_Record);
   procedure Calculate_Facets
     (the_matrix : Matrix_Access; Settings : Settings_Record);
   function Calculate_Normal
     (P0 : Point; P1 : Point; P2 : Point) return Vector;

end Lithophane.STL;
