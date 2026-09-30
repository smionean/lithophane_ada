------------------------------------------------------------------------------
--  lithophane-image_utilities.ads
--
--  Specification of Lithophane.Image_Utilities: down-scale the input image
--  before the mesh is built.
--    * Calculate_New_Image_Size -- new width or height after shrinking both
--      sides by one factor so the larger side lands on Settings.max_size,
--      preserving the aspect ratio;
--    * Resize_Image -- return a new greyscale matrix (Matrix_Grey_Type)
--      resampled to the given size (nearest-neighbour, truncated source
--      index).
--
--  Created : 2026-09-04
--  Author  : Simon Beàn
------------------------------------------------------------------------------

package Lithophane.Image_Utilities is
   type Dimension_Name is (tWIDTH, tHEIGHT);

   --  Return the new width or height (selected by Which) after scaling both
   --  sides by the same factor, so the aspect ratio is preserved and the
   --  larger side becomes exactly Settings.max_size. The factor is always
   --  applied: the caller must only call this when the image is too large.
   function Calculate_New_Image_Size
     (width    : Natural;
      height   : Natural;
      Which    : Dimension_Name;
      Settings : Settings_Record) return Natural;

   function Resize_Image
     (the_image  : Matrix_Grey_Access;
      new_width  : Natural;
      new_height : Natural) return Matrix_Grey_Access;
end Lithophane.Image_Utilities;
