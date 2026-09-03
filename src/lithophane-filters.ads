------------------------------------------------------------------------------
--  lithophane-filters.ads
--
--  Specification of Lithophane.Filters: image pre-processing applied to the
--  greyscale matrix before the mesh is built.
--    * Create_Bartlett/Gauss/Square/Sharpen_Filter -- build a square,
--      odd-sized convolution kernel (Matrix_Filter_Type);
--    * Apply_On_Point -- convolve one kernel position, edge-clamped and
--      normalised by the sum of the kernel weights;
--    * Apply_Filter -- convolve a whole image (out of place);
--    * Apply_Threshold_Filter -- clamp every pixel below a threshold to 0.
--
--  Created : 2026-08-23
--  Author  : Simon Beàn
------------------------------------------------------------------------------

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

   function Apply_On_Point
     (the_image  : Matrix_Type;
      pos_c      : Natural;
      pos_l      : Natural;
      the_filter : Matrix_Filter_Type) return Color_Type;
   --  Convolve the_filter, centred on (pos_c, pos_l), with the_image and
   --  return the normalised (sum of the filter weights) result, clamped to
   --  Color_Type. Positions outside the image are clamped to its edges.

   procedure Apply_Filter
     (the_image : Matrix_Access; the_filter : Matrix_Filter_Type);

   procedure Apply_Threshold_Filter
     (the_image : Matrix_Access; the_threshold : Color_Type);

end Lithophane.Filters;
