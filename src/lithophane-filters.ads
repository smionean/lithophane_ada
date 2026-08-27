package Lithophane.Filters is

   function Create_Bartlett_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   with Pre => X = Y and then X mod 2 = 1;

   function Create_Gauss_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   with Pre => X = Y and then X mod 2 = 1;

   function Create_Square_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type
   with Pre => X = Y and then X mod 2 = 1;

   function Create_Sharpen_Filter
     (X : Integer; Y : Integer) return Matrix_Filter_Type;

   --  procedure Apply_Bartlett;
   --  procedure Apply_Gauss;
   --  procedure Apply_Square;
   --  procedure Apply_Sharpen;
   procedure Apply_Filter
     (the_image : Matrix_Access; the_filter : Matrix_Filter_Type);

   procedure Apply_Threshold_Filter
     (the_image : Matrix_Access; the_threshold : Color_Type);

end Lithophane.Filters;
