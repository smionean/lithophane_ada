------------------------------------------------------------------------------
--  image_utilities_tests.adb
--
--  Regression tests for Lithophane.Image_Utilities: the size of a shrunk
--  image and its nearest-neighbour resampling.
------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;

with Lithophane;                 use Lithophane;
with Lithophane.Image_Utilities; use Lithophane.Image_Utilities;

package body Image_Utilities_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   procedure Check_Size
     (Width, Height, Max_Size : Natural; New_Width, New_Height : Natural)
   is
      Settings : constant Settings_Record :=
        (max_size => Max_Size, others => <>);
      Got_W    : constant Natural :=
        Calculate_New_Image_Size (Width, Height, tWIDTH, Settings);
      Got_H    : constant Natural :=
        Calculate_New_Image_Size (Width, Height, tHEIGHT, Settings);
   begin
      Assert
        (Got_W = New_Width and then Got_H = New_Height,
         Width'Image
         & " x"
         & Height'Image
         & " limited to"
         & Max_Size'Image
         & ": expected"
         & New_Width'Image
         & " x"
         & New_Height'Image
         & ", got"
         & Got_W'Image
         & " x"
         & Got_H'Image);
   end Check_Size;

   procedure Larger_Side_Lands_On_Max_Size (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check_Size (3_000, 1_500, 1_500, 1_500, 750);
      Check_Size (1_500, 3_000, 1_500, 750, 1_500);
      Check_Size (2_000, 2_000, 500, 500, 500);
      Check_Size (6, 5, 4, 4, 3);
   end Larger_Side_Lands_On_Max_Size;

   procedure Smaller_Side_Is_At_Least_One (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Check_Size (1_000, 1, 10, 10, 1);
      Check_Size (1, 1_000, 10, 1, 10);
   end Smaller_Side_Is_At_Least_One;

   --  A matrix whose pixels all differ: 0.01 * (10 * column + row).
   function Numbered
     (First_C, Last_C, First_L, Last_L : Natural) return Matrix_Grey_Access
   is
      Image : constant Matrix_Grey_Access :=
        new Matrix_Grey_Type (First_C .. Last_C, First_L .. Last_L);
   begin
      for C in Image'Range (1) loop
         for L in Image'Range (2) loop
            Image (C, L) :=
              Grey_Type
                (0.01 * Float (10 * (C - First_C + 1) + L - First_L + 1));
         end loop;
      end loop;
      return Image;
   end Numbered;

   procedure Halving_Keeps_Every_Other_Pixel (T : in out Test_Case) is
      pragma Unreferenced (T);
      Source : constant Matrix_Grey_Access := Numbered (1, 4, 1, 6);
      Half   : constant Matrix_Grey_Access := Resize_Image (Source, 2, 3);
   begin
      Assert
        (Half'First (1) = 1
         and then Half'Last (1) = 2
         and then Half'First (2) = 1
         and then Half'Last (2) = 3,
         "the resized image is not indexed 1 .. 2, 1 .. 3");
      for C in 1 .. 2 loop
         for L in 1 .. 3 loop
            Assert
              (Half (C, L) = Source (2 * C - 1, 2 * L - 1),
               "wrong source pixel for" & C'Image & L'Image);
         end loop;
      end loop;
   end Halving_Keeps_Every_Other_Pixel;

   procedure Same_Size_Is_A_Copy (T : in out Test_Case) is
      pragma Unreferenced (T);
      Source : constant Matrix_Grey_Access := Numbered (1, 5, 1, 3);
      Copy   : constant Matrix_Grey_Access := Resize_Image (Source, 5, 3);
   begin
      Assert (Copy.all = Source.all, "resizing to the same size changed it");
   end Same_Size_Is_A_Copy;

   procedure Source_Bounds_Do_Not_Matter (T : in out Test_Case) is
      pragma Unreferenced (T);
      From_1 : constant Matrix_Grey_Access :=
        Resize_Image (Numbered (1, 7, 1, 5), 3, 2);
      From_0 : constant Matrix_Grey_Access :=
        Resize_Image (Numbered (0, 6, 10, 14), 3, 2);
   begin
      Assert
        (From_1.all = From_0.all,
         "the result depends on the bounds of the source");
   end Source_Bounds_Do_Not_Matter;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Larger_Side_Lands_On_Max_Size'Access,
         "the larger side is shrunk to max_size, aspect ratio kept");
      Register_Routine
        (T,
         Smaller_Side_Is_At_Least_One'Access,
         "the smaller side never drops to 0");
      Register_Routine
        (T,
         Halving_Keeps_Every_Other_Pixel'Access,
         "halving keeps every other pixel");
      Register_Routine
        (T, Same_Size_Is_A_Copy'Access, "resizing to the same size");
      Register_Routine
        (T,
         Source_Bounds_Do_Not_Matter'Access,
         "resizing a matrix that is not indexed from 1");
   end Register_Tests;

end Image_Utilities_Tests;
