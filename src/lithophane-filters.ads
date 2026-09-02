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
   function Apply_On_Point
     (the_image  : Matrix_Type;
      pos_c      : Natural;
      pos_l      : Natural;
      the_filter : Matrix_Filter_Type) return Color_Range;
   --  Convolve the_filter, centred on (pos_c, pos_l), with the_image and
   --  return the normalised (sum of the filter weights) result, clamped to
   --  Color_Range. Positions outside the image are clamped to its edges.

   procedure Apply_Filter
     (the_image : Matrix_Access; the_filter : Matrix_Filter_Type);

   procedure Apply_Threshold_Filter
     (the_image : Matrix_Access; the_threshold : Color_Range);

end Lithophane.Filters;
