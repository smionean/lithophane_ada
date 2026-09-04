------------------------------------------------------------------------------
--  lithophane-image_utilities.adb
--
--  Body of Lithophane.Image_Utilities.
--    * Calculate_New_Image_Size scales both sides by
--      Settings.max_size / max(width, height), floors each, keeps a
--      minimum of 1, and returns the requested dimension.
--    * Resize_Image allocates a new Matrix_Type of the target size and
--      fills it by nearest-neighbour sampling, flooring the mapped source
--      index so it never steps past the last column/row.
--
--  Created : 2026-09-04
--  Author  : Simon Beàn
------------------------------------------------------------------------------

package body Lithophane.Image_Utilities is

   function Calculate_New_Image_Size
     (width    : Natural;
      height   : Natural;
      Which    : Dimension_Name;
      Settings : Settings_Record) return Natural
   is
      new_width  : Natural := width;
      new_height : Natural := height;
      largest    : constant Natural := Natural'Max (width, height);
      scale      : Float;
   begin
      --  Shrink both dimensions by the same factor so the aspect ratio is
      --  preserved and the larger side ends up at exactly max_size.
      scale := Float (Settings.max_size) / Float (largest);
      new_width :=
        Natural'Max (1, Natural (Float'Floor (Float (width) * scale)));
      new_height :=
        Natural'Max (1, Natural (Float'Floor (Float (height) * scale)));
      case Which is
         when tWIDTH  =>
            return new_width;

         when tHEIGHT =>
            return new_height;
      end case;
   end Calculate_New_Image_Size;

   function Resize_Image
     (the_image : Matrix_Access; new_width : Natural; new_height : Natural)
      return Matrix_Access
   is
      old_width  : constant Natural := the_image'Length (1);
      old_height : constant Natural := the_image'Length (2);
      new_image  : constant Matrix_Access :=
        new Matrix_Type (1 .. new_width, 1 .. new_height);
      x_ratio    : constant Float := Float (old_width) / Float (new_width);
      y_ratio    : constant Float := Float (old_height) / Float (new_height);
   begin
      for new_x in 1 .. new_width loop
         for new_y in 1 .. new_height loop
            declare
               --  Truncate (not round) so the source index can never step
               --  past the last column/row on the final iteration.
               old_x : constant Natural :=
                 Natural (Float'Floor (Float (new_x - 1) * x_ratio)) + 1;
               old_y : constant Natural :=
                 Natural (Float'Floor (Float (new_y - 1) * y_ratio)) + 1;
            begin
               new_image (new_x, new_y) :=
                 the_image
                   (the_image'First (1) + old_x - 1,
                    the_image'First (2) + old_y - 1);
            end;
         end loop;
      end loop;
      return new_image;
   end Resize_Image;
end Lithophane.Image_Utilities;
