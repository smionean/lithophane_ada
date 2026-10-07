------------------------------------------------------------------------------
--  mesh_tests.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Regression tests for Lithophane.Calculate_Normal and
--  Lithophane.Calculate_Facets: the height map must become a closed mesh
--  whose relief culminates at Settings.height, on a base at Z = -2.
------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;

with Lithophane;          use Lithophane;
with Test_Support;        use Test_Support;
with Test_Support.Meshes; use Test_Support.Meshes;

package body Mesh_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   Base_Z : constant Float := -2.0;

   function With_Height (Height : Float) return Settings_Record
   is (height => Height, others => <>);

   --  A 5 x 4 height map with a flat margin, a slope and a peak.
   function Relief return Matrix_Grey_Access is
      Image : constant Matrix_Grey_Access := Flat_Matrix (5, 4, 0.0);
   begin
      Image (2, 2) := 0.25;
      Image (3, 2) := 0.5;
      Image (3, 3) := 0.125;
      return Image;
   end Relief;

   procedure Assert_Vector (Actual : Vector; X, Y, Z : Float; What : String) is
   begin
      Assert_Near (Actual.vx, X, What & " (x)");
      Assert_Near (Actual.vy, Y, What & " (y)");
      Assert_Near (Actual.vz, Z, What & " (z)");
   end Assert_Vector;

   procedure Normal_Of_A_Triangle (T : in out Test_Case) is
      pragma Unreferenced (T);
      O : constant Point := (0.0, 0.0, 0.0);
      X : constant Point := (4.0, 0.0, 0.0);
      Y : constant Point := (0.0, 3.0, 0.0);
      Z : constant Point := (0.0, 0.0, 2.0);
   begin
      Assert_Vector (Calculate_Normal (O, X, Y), 0.0, 0.0, 1.0, "O X Y");
      Assert_Vector (Calculate_Normal (O, Y, X), 0.0, 0.0, -1.0, "O Y X");
      Assert_Vector (Calculate_Normal (O, Y, Z), 1.0, 0.0, 0.0, "O Y Z");
      Assert_Vector (Calculate_Normal (O, Z, X), 0.0, 1.0, 0.0, "O Z X");
   end Normal_Of_A_Triangle;

   procedure Normal_Of_A_Null_Triangle (T : in out Test_Case) is
      pragma Unreferenced (T);
      A : constant Point := (1.0, 1.0, 1.0);
      B : constant Point := (2.0, 2.0, 2.0);
      C : constant Point := (3.0, 3.0, 3.0);
   begin
      Assert_Vector (Calculate_Normal (A, B, C), 0.0, 0.0, 0.0, "aligned");
      Assert_Vector (Calculate_Normal (A, A, B), 0.0, 0.0, 0.0, "two points");
   end Normal_Of_A_Null_Triangle;

   procedure Smallest_Mesh (T : in out Test_Case) is
      pragma Unreferenced (T);
      Mesh : constant Facets.Vector :=
        Calculate_Facets (Flat_Matrix (2, 2, 1.0), With_Height (10.0));
   begin
      --  A box: 2 triangles for each of its 6 faces.
      Assert
        (Natural (Mesh.Length) = 12,
         "expected 12 facets, got" & Mesh.Length'Image);
      Assert (Open_Edges (Mesh) = 0, "the box is not closed");
   end Smallest_Mesh;

   procedure Brightest_Grey_Reaches_Height (T : in out Test_Case) is
      pragma Unreferenced (T);
      Mesh : constant Facets.Vector :=
        Calculate_Facets (Relief, With_Height (7.0));
      Size : constant Box := Bounding_Box (Mesh);
   begin
      Assert_Near (Size.Max.pz, 7.0, "top of the relief");
      Assert_Near (Size.Min.pz, Base_Z, "bottom of the base");

      --  The other greys are raised in proportion: 0.5 is the brightest.
      Assert (Has_Vertex (Mesh, 3.0, 2.0, 7.0), "no vertex for grey 0.5");
      Assert (Has_Vertex (Mesh, 2.0, 2.0, 3.5), "no vertex for grey 0.25");
      Assert (Has_Vertex (Mesh, 3.0, 3.0, 1.75), "no vertex for grey 0.125");
      Assert (Has_Vertex (Mesh, 1.0, 1.0, 0.0), "no vertex for grey 0.0");
   end Brightest_Grey_Reaches_Height;

   procedure Black_Image_Is_Flat (T : in out Test_Case) is
      pragma Unreferenced (T);
      Size : constant Box :=
        Bounding_Box
          (Calculate_Facets (Flat_Matrix (4, 4, 0.0), With_Height (10.0)));
   begin
      Assert_Near (Size.Max.pz, 0.0, "top of a black image");
      Assert_Near (Size.Min.pz, Base_Z, "bottom of the base");
   end Black_Image_Is_Flat;

   procedure One_Unit_Per_Pixel (T : in out Test_Case) is
      pragma Unreferenced (T);
      Size : constant Box :=
        Bounding_Box (Calculate_Facets (Relief, With_Height (10.0)));
   begin
      Assert_Near (Size.Min.px, 1.0, "min X");
      Assert_Near (Size.Max.px, 5.0, "max X");
      Assert_Near (Size.Min.py, 1.0, "min Y");
      Assert_Near (Size.Max.py, 4.0, "max Y");
   end One_Unit_Per_Pixel;

   procedure Check_Closed (Image : Matrix_Grey_Access; What : String) is
      Mesh : constant Facets.Vector :=
        Calculate_Facets (Image, With_Height (10.0));
   begin
      Assert
        (Open_Edges (Mesh) = 0,
         What & ":" & Open_Edges (Mesh)'Image & " open edges");
      Assert
        (Misoriented_Edges (Mesh) = 0,
         What & ": the triangles do not all turn the same way");
      Assert
        (Degenerate_Facets (Mesh) = 0,
         What & ":" & Degenerate_Facets (Mesh)'Image & " null triangles");
   end Check_Closed;

   procedure Mesh_Is_Closed (T : in out Test_Case) is
      pragma Unreferenced (T);
      Slope   : constant Matrix_Grey_Access := Flat_Matrix (6, 5, 0.0);
      Plateau : constant Matrix_Grey_Access := Flat_Matrix (9, 8, 0.2);
   begin
      for C in Slope'Range (1) loop
         for L in Slope'Range (2) loop
            Slope (C, L) := Grey_Type (0.03 * Float (C * L));
         end loop;
      end loop;

      --  Flat areas of different heights, merged into rectangles, next to
      --  cells that are not flat.
      for C in 4 .. 7 loop
         for L in 3 .. 6 loop
            Plateau (C, L) := 0.8;
         end loop;
      end loop;
      Plateau (9, 8) := 1.0;

      Check_Closed (Slope, "slope");
      Check_Closed (Relief, "relief");
      Check_Closed (Plateau, "plateau");
      Check_Closed (Flat_Matrix (10, 7, 1.0), "flat image");
      Check_Closed (Flat_Matrix (2, 9, 0.5), "one cell wide image");
   end Mesh_Is_Closed;

   procedure Normals_Are_Unit_Vectors (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      for F of Calculate_Facets (Relief, With_Height (10.0)) loop
         Assert_Near
           (F.Normal.vx ** 2 + F.Normal.vy ** 2 + F.Normal.vz ** 2,
            1.0,
            "length of a normal");
      end loop;
   end Normals_Are_Unit_Vectors;

   --  Seen from outside, the vertices of every facet turn counter-clockwise:
   --  on a box, the normal this gives is known for each face.
   procedure Facets_Face_Outwards (T : in out Test_Case) is
      pragma Unreferenced (T);
      Mesh : constant Facets.Vector :=
        Calculate_Facets (Flat_Matrix (4, 3, 1.0), With_Height (5.0));

      type Axis is (X, Y, Z);

      function On_Face (F : Facet; Along : Axis; At_Value : Float)
         return Boolean
      is (case Along is
            when X =>
              F.Vertex_A.px = At_Value
              and then F.Vertex_B.px = At_Value
              and then F.Vertex_C.px = At_Value,
            when Y =>
              F.Vertex_A.py = At_Value
              and then F.Vertex_B.py = At_Value
              and then F.Vertex_C.py = At_Value,
            when Z =>
              F.Vertex_A.pz = At_Value
              and then F.Vertex_B.pz = At_Value
              and then F.Vertex_C.pz = At_Value);
   begin
      for F of Mesh loop
         declare
            Turn : constant Vector :=
              Calculate_Normal (F.Vertex_A, F.Vertex_B, F.Vertex_C);
         begin
            if On_Face (F, Z, 5.0) then
               Assert_Vector (Turn, 0.0, 0.0, 1.0, "top face");
               Assert_Vector (F.Normal, 0.0, 0.0, 1.0, "top face normal");
            elsif On_Face (F, Z, Base_Z) then
               Assert_Vector (Turn, 0.0, 0.0, -1.0, "bottom face");
               Assert_Vector (F.Normal, 0.0, 0.0, -1.0, "bottom face normal");
            elsif On_Face (F, X, 1.0) then
               Assert_Vector (Turn, -1.0, 0.0, 0.0, "face X = 1");
            elsif On_Face (F, X, 4.0) then
               Assert_Vector (Turn, 1.0, 0.0, 0.0, "face X = 4");
            elsif On_Face (F, Y, 1.0) then
               Assert_Vector (Turn, 0.0, -1.0, 0.0, "face Y = 1");
            elsif On_Face (F, Y, 3.0) then
               Assert_Vector (Turn, 0.0, 1.0, 0.0, "face Y = 3");
            else
               Assert (False, "a facet lies on no face of the box");
            end if;
         end;
      end loop;
   end Facets_Face_Outwards;

   --  Flat areas are merged instead of getting two triangles per pixel.
   procedure Flat_Areas_Are_Merged (T : in out Test_Case) is
      pragma Unreferenced (T);
      Cells     : constant := 29;
      Mesh      : constant Facets.Vector :=
        Calculate_Facets
          (Flat_Matrix (Cells + 1, Cells + 1, 1.0), With_Height (10.0));
      Per_Pixel : constant Natural := 2 * 2 * Cells * Cells + 4 * 2 * Cells;
   begin
      Assert
        (Natural (Mesh.Length) < Per_Pixel / 4,
         "a flat image gives" & Mesh.Length'Image & " facets");
   end Flat_Areas_Are_Merged;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Normal_Of_A_Triangle'Access, "normal of a triangle");
      Register_Routine
        (T, Normal_Of_A_Null_Triangle'Access, "normal of a null triangle");
      Register_Routine (T, Smallest_Mesh'Access, "2 x 2 image gives a box");
      Register_Routine
        (T,
         Brightest_Grey_Reaches_Height'Access,
         "the brightest grey is raised to Settings.height");
      Register_Routine
        (T, Black_Image_Is_Flat'Access, "a black image has no relief");
      Register_Routine
        (T, One_Unit_Per_Pixel'Access, "X and Y follow the matrix indices");
      Register_Routine (T, Mesh_Is_Closed'Access, "the mesh is closed");
      Register_Routine
        (T, Normals_Are_Unit_Vectors'Access, "normals are unit vectors");
      Register_Routine
        (T, Facets_Face_Outwards'Access, "the facets face outwards");
      Register_Routine
        (T, Flat_Areas_Are_Merged'Access, "flat areas are merged");
   end Register_Tests;

end Mesh_Tests;
