------------------------------------------------------------------------------
--  lithophane-image_utilities.ads
--
--  Specification of Lithophane.Image_Utilities: down-scale the input image
--  before the mesh is built.
--    * Calculate_New_Image_Size -- new width or height after shrinking both
--      sides by one factor so the larger side lands on Settings.max_size,
--      preserving the aspect ratio;
--    * Resize_Image -- return a new matrix resampled to the given size
--      (nearest-neighbour, truncated source index).
--
--  Created : 2026-09-04
--  Author  : Simon Beàn
------------------------------------------------------------------------------

package Lithophane.Image_Utilities is
   type Dimension_Name is (tWIDTH, tHEIGHT);

   --  Scale width/height down, preserving aspect ratio, so that neither
   --  exceeds 1500. Leaves them unchanged when both already fit.
   function Calculate_New_Image_Size
     (width    : Natural;
      height   : Natural;
      Which    : Dimension_Name;
      Settings : Settings_Record) return Natural;

   function Resize_Image
     (the_image : Matrix_Access; new_width : Natural; new_height : Natural)
      return Matrix_Access;
end Lithophane.Image_Utilities;
