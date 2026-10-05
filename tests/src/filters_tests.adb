------------------------------------------------------------------------------
--  filters_tests.adb
--
--  Regression tests for Lithophane.Filters: the kernels, the convolution
--  of one point and of a whole image, and the threshold.
------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;

with Lithophane;         use Lithophane;
with Lithophane.Filters; use Lithophane.Filters;
with Test_Support;       use Test_Support;

package body Filters_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   --  A 3 x 3 image of 0.5 with a brighter centre.
   function Bump return Matrix_Grey_Access is
      Image : constant Matrix_Grey_Access := Flat_Matrix (3, 3, 0.5);
   begin
      Image (2, 2) := 0.6;
      return Image;
   end Bump;

   function Sum (Kernel : Matrix_Filter_Type) return Integer is
      Result : Integer := 0;
   begin
      for Weight of Kernel loop
         Result := Result + Weight;
      end loop;
      return Result;
   end Sum;

   procedure Sharpen_Kernel (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      for Size in 3 .. 7 loop
         if Size mod 2 = 1 then
            declare
               Kernel : constant Matrix_Filter_Type :=
                 Create_Sharpen_Filter (Size, Size);
               Middle : constant Positive := (Size + 1) / 2;
            begin
               Assert
                 (Kernel'Length (1) = Size and then Kernel'Length (2) = Size,
                  "sharpen kernel is not" & Size'Image & " wide");
               Assert
                 (Sum (Kernel) = 1,
                  "sharpen weights do not sum to 1 for size" & Size'Image);
               Assert
                 (Kernel (Middle, Middle) = Size * Size,
                  "wrong centre weight for size" & Size'Image);
               Assert
                 (Kernel (1, 1) = -1 and then Kernel (Size, Size) = -1,
                  "wrong outer weight for size" & Size'Image);
            end;
         end if;
      end loop;
   end Sharpen_Kernel;

   procedure Kernel_Sizes (T : in out Test_Case) is
      pragma Unreferenced (T);

      procedure Check (Kernel : Matrix_Filter_Type; Filter : String) is
      begin
         Assert
           (Kernel'First (1) = 1
            and then Kernel'First (2) = 1
            and then Kernel'Last (1) = 5
            and then Kernel'Last (2) = 5,
            Filter & " kernel is not indexed 1 .. 5, 1 .. 5");
      end Check;
   begin
      Check (Create_Bartlett_Filter (5, 5), "bartlett");
      Check (Create_Gauss_Filter (5, 5), "gauss");
      Check (Create_Square_Filter (5, 5), "square");
      Check (Create_Sharpen_Filter (5, 5), "sharpen");
   end Kernel_Sizes;

   --  Whatever its weights, a normalised kernel leaves a uniform image as
   --  it is.
   procedure Uniform_Image_Is_Unchanged (T : in out Test_Case) is
      pragma Unreferenced (T);

      procedure Check (Kernel : Matrix_Filter_Type; Filter : String) is
         Image : constant Matrix_Grey_Access := Flat_Matrix (6, 4, 0.3);
      begin
         Apply_Filter (Image, Kernel);
         for Grey of Image.all loop
            Assert_Near (Float (Grey), 0.3, Filter & " on a uniform image");
         end loop;
      end Check;
   begin
      Check (Create_Bartlett_Filter (3, 3), "bartlett");
      Check (Create_Gauss_Filter (3, 3), "gauss");
      Check (Create_Square_Filter (5, 5), "square");
      Check (Create_Sharpen_Filter (5, 5), "sharpen");
   end Uniform_Image_Is_Unchanged;

   procedure Convolution_Of_A_Point (T : in out Test_Case) is
      pragma Unreferenced (T);
      Image   : constant Matrix_Grey_Access := Bump;
      Sharpen : constant Matrix_Filter_Type := Create_Sharpen_Filter (3, 3);
      Square  : constant Matrix_Filter_Type (1 .. 3, 1 .. 3) :=
        [others => [others => 1]];
   begin
      --  (8 * 0.5 + 0.6) / 9
      Assert_Near
        (Float (Apply_On_Point (Image.all, 2, 2, Square)),
         4.6 / 9.0,
         "mean of the 3 x 3 neighbourhood");

      --  9 * 0.5 - (7 * 0.5 + 0.6)
      Assert_Near
        (Float (Apply_On_Point (Image.all, 1, 2, Sharpen)),
         0.4,
         "sharpen next to the bump");
   end Convolution_Of_A_Point;

   procedure Result_Is_Clamped (T : in out Test_Case) is
      pragma Unreferenced (T);
      Image   : constant Matrix_Grey_Access := Bump;
      Sharpen : constant Matrix_Filter_Type := Create_Sharpen_Filter (3, 3);
   begin
      --  9 * 0.6 - 8 * 0.5 = 1.4
      Assert_Near
        (Float (Apply_On_Point (Image.all, 2, 2, Sharpen)),
         1.0,
         "result above 1.0");

      --  9 * 0.0 - 8 * 1.0 = -8.0
      Image.all := [others => [others => 1.0]];
      Image (2, 2) := 0.0;
      Assert_Near
        (Float (Apply_On_Point (Image.all, 2, 2, Sharpen)),
         0.0,
         "result below 0.0");
   end Result_Is_Clamped;

   --  Outside the image, the nearest pixel of the edge is used.
   procedure Edges_Are_Extended (T : in out Test_Case) is
      pragma Unreferenced (T);
      Image   : constant Matrix_Grey_Access := Bump;
      Sharpen : constant Matrix_Filter_Type := Create_Sharpen_Filter (3, 3);
   begin
      --  The corner sees itself 4 times, two edge pixels twice and the
      --  bump once: 9 * 0.5 - (3 * 0.5 + 4 * 0.5 + 0.6)
      Assert_Near
        (Float (Apply_On_Point (Image.all, 1, 1, Sharpen)),
         0.4,
         "sharpen in a corner");
      Assert_Near
        (Float (Apply_On_Point (Image.all, 3, 3, Sharpen)),
         0.4,
         "sharpen in the opposite corner");
   end Edges_Are_Extended;

   procedure Null_Kernel_Is_Identity (T : in out Test_Case) is
      pragma Unreferenced (T);
      Image  : constant Matrix_Grey_Access := Bump;
      Kernel : constant Matrix_Filter_Type (1 .. 3, 1 .. 3) :=
        [others => [others => 0]];
   begin
      Apply_Filter (Image, Kernel);
      Assert (Image.all = Bump.all, "a null kernel changed the image");
   end Null_Kernel_Is_Identity;

   --  Every point is filtered from the original image, not from the
   --  neighbours already rewritten.
   procedure Whole_Image_Is_Filtered_From_The_Source (T : in out Test_Case) is
      pragma Unreferenced (T);
      Image : constant Matrix_Grey_Access := Bump;
   begin
      Apply_Filter (Image, Create_Sharpen_Filter (3, 3));
      for C in Image'Range (1) loop
         for L in Image'Range (2) loop
            Assert_Near
              (Float (Image (C, L)),
               (if C = 2 and then L = 2 then 1.0 else 0.4),
               "sharpened pixel" & C'Image & L'Image);
         end loop;
      end loop;
   end Whole_Image_Is_Filtered_From_The_Source;

   procedure Threshold (T : in out Test_Case) is
      pragma Unreferenced (T);
      Image : constant Matrix_Grey_Access := Flat_Matrix (2, 2, 0.5);
   begin
      Image (1, 1) := 0.49;
      Image (2, 1) := 0.0;
      Image (2, 2) := 1.0;

      Apply_Threshold_Filter (Image, 0.5);
      Assert (Image (1, 1) = 0.0, "a pixel below the threshold was kept");
      Assert (Image (1, 2) = 0.5, "a pixel at the threshold was cut");
      Assert (Image (2, 1) = 0.0, "a black pixel was changed");
      Assert (Image (2, 2) = 1.0, "a pixel above the threshold was cut");
   end Threshold;

   procedure Null_Threshold_Keeps_Everything (T : in out Test_Case) is
      pragma Unreferenced (T);
      Image : constant Matrix_Grey_Access := Bump;
   begin
      Image (1, 1) := 0.001;
      Apply_Threshold_Filter (Image, 0.0);
      Assert (Image (1, 1) = 0.001, "threshold 0.0 cut a pixel");
      Assert (Image (2, 2) = 0.6, "threshold 0.0 changed a pixel");
   end Null_Threshold_Keeps_Everything;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Sharpen_Kernel'Access, "sharpen kernel weights");
      Register_Routine (T, Kernel_Sizes'Access, "kernels have the given size");
      Register_Routine
        (T,
         Uniform_Image_Is_Unchanged'Access,
         "a uniform image is left unchanged");
      Register_Routine
        (T, Convolution_Of_A_Point'Access, "convolution of one point");
      Register_Routine
        (T, Result_Is_Clamped'Access, "the result is clamped to 0.0 .. 1.0");
      Register_Routine
        (T, Edges_Are_Extended'Access, "the edges of the image are extended");
      Register_Routine
        (T, Null_Kernel_Is_Identity'Access, "a null kernel changes nothing");
      Register_Routine
        (T,
         Whole_Image_Is_Filtered_From_The_Source'Access,
         "the image is filtered from a copy of itself");
      Register_Routine (T, Threshold'Access, "threshold");
      Register_Routine
        (T,
         Null_Threshold_Keeps_Everything'Access,
         "a threshold of 0.0 keeps every pixel");
   end Register_Tests;

end Filters_Tests;
