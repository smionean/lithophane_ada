package body Lithophane.Filters is

   function Create_Bartlett_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   is
      a_filter : constant Matrix_Filter_Type (1 .. X, 1 .. Y) :=
        [for J in 1 .. X => [for K in 1 .. Y => 0]];
   begin
      return a_filter;
   end Create_Bartlett_Filter;

   function Create_Gauss_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   is
      a_filter : constant Matrix_Filter_Type (1 .. X, 1 .. Y) :=
        [for J in 1 .. X => [for K in 1 .. Y => 0]];
   begin
      return a_filter;
   end Create_Gauss_Filter;

   function Create_Square_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   is
      a_filter : constant Matrix_Filter_Type (1 .. X, 1 .. Y) :=
        [for J in 1 .. X => [for K in 1 .. Y => 0]];
   begin
      return a_filter;
   end Create_Square_Filter;

   function Create_Sharpen_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   is
      a_filter : constant Matrix_Filter_Type (1 .. X, 1 .. Y) :=
        [for J in 1 .. X => [for K in 1 .. Y => 0]];
   begin
      return a_filter;
   end Create_Sharpen_Filter;

   procedure Apply_Filter
     (the_image : Matrix_Access; the_filter : Matrix_Filter_Type) is
   begin
      null;
   end Apply_Filter;

   procedure Apply_Threshold_Filter
     (the_image : Matrix_Access; the_threshold : Color_Type) is
   begin
      for c in 1 .. the_image.all'Last (1) loop
         for l in 1 .. the_image.all'Last (2) loop
            if the_image.all (c, l) < the_threshold then
               the_image.all (c, l) := Color_Type'First;
            else
               the_image.all (c, l) := the_image.all (c, l);
            end if;

         end loop;
      end loop;

   end Apply_Threshold_Filter;

end Lithophane.Filters;
