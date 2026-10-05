------------------------------------------------------------------------------
--  file3mf_tests.adb
--
--  Regression tests for Lithophane.File3mf: the 3MF file must be a valid
--  ZIP/OPC package holding a welded, closed mesh, scaled to the requested
--  size in millimetres.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Interfaces;

with AUnit.Assertions; use AUnit.Assertions;

with Lithophane;          use Lithophane;
with Lithophane.File3mf;  use Lithophane.File3mf;
with Test_Support;        use Test_Support;
with Test_Support.Meshes; use Test_Support.Meshes;

package body File3mf_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   Relief_Height : constant Float := 6.0;
   Base          : constant Float := 2.0;

   --  7 x 5 pixels, i.e. 6 x 4 units before scaling.
   function Sample return Facets.Vector is
      Image : constant Matrix_Grey_Access := Flat_Matrix (7, 5, 0.25);
   begin
      Image (2, 2) := 1.0;
      Image (5, 4) := 0.5;
      return
        Calculate_Facets (Image, (height => Relief_Height, others => <>));
   end Sample;

   --  Write the sample as <Name>.3mf with the requested dimensions and
   --  read it back.
   function Written
     (Name : String; Width, Height, Depth : Float := 0.0) return Model is
   begin
      Reset_Scratch;
      Dump_3mf
        (Sample,
         (outfilename => To_Unbounded_String (Scratch (Name)),
          dimensions  => (Width, Height, Depth),
          others      => <>));
      return Read_3MF (Scratch (Name & ".3mf"));
   end Written;

   procedure Assert_Size
     (Mesh : Model; Width, Height, Depth : Float; What : String)
   is
      Size : constant Box := Bounding_Box (Mesh);
   begin
      Assert_Near (Size.Max.px - Size.Min.px, Width, What & ": width", 1.0e-3);
      Assert_Near
        (Size.Max.py - Size.Min.py, Height, What & ": height", 1.0e-3);
      Assert_Near (Size.Max.pz - Size.Min.pz, Depth, What & ": depth", 1.0e-3);

      --  Centred on the origin, lying on Z = 0.
      Assert_Near (Size.Min.px, -Width / 2.0, What & ": min X", 1.0e-3);
      Assert_Near (Size.Min.py, -Height / 2.0, What & ": min Y", 1.0e-3);
      Assert_Near (Size.Min.pz, 0.0, What & ": min Z", 1.0e-3);
   end Assert_Size;

   procedure Package_Layout (T : in out Test_Case) is
      pragma Unreferenced (T);
      use type Interfaces.Unsigned_32;
      Mesh  : constant Model := Written ("package");
      Parts : constant Zip_Part_Vectors.Vector :=
        Read_Zip (Scratch ("package.3mf"));
      pragma Unreferenced (Mesh);
   begin
      Assert
        (Natural (Parts.Length) = 3
         and then To_String (Parts (1).Name) = "[Content_Types].xml"
         and then To_String (Parts (2).Name) = "_rels/.rels"
         and then To_String (Parts (3).Name) = "3D/3dmodel.model",
         "unexpected parts in the package");

      for Part of Parts loop
         Assert
           (CRC_32 (To_String (Part.Data)) = Part.CRC,
            "wrong CRC-32 for " & To_String (Part.Name));
      end loop;

      Assert
        (Contains
           (To_String (Parts (1).Data),
            "Extension=""model"" ContentType=""application/"
            & "vnd.ms-package.3dmanufacturing-3dmodel+xml"""),
         "the content type of the model is not declared");
      Assert
        (Contains
           (To_String (Parts (2).Data), "Target=""/3D/3dmodel.model"""),
         "the relationships do not point to the model");
      Assert
        (Contains (To_String (Parts (3).Data), "<model unit=""millimeter"""),
         "the model is not in millimetres");
      Assert
        (Contains (To_String (Parts (3).Data), "<item objectid=""1""/>"),
         "the object is not in the build");
   end Package_Layout;

   procedure Mesh_Is_Welded_And_Closed (T : in out Test_Case) is
      pragma Unreferenced (T);
      Mesh : constant Model := Written ("welded");
   begin
      Assert
        (Natural (Mesh.Triangles.Length) = Natural (Sample.Length),
         "expected" & Sample.Length'Image & " triangles");
      Assert
        (Natural (Mesh.Vertices.Length) < Natural (Mesh.Triangles.Length),
         "the vertices are not shared between triangles");
      for Corners of Mesh.Triangles loop
         Assert
           (Corners.V1 <= Mesh.Vertices.Last_Index
            and then Corners.V2 <= Mesh.Vertices.Last_Index
            and then Corners.V3 <= Mesh.Vertices.Last_Index,
            "a triangle refers to a vertex that does not exist");
      end loop;
      Assert
        (Open_Edges (Mesh) = 0,
         "the mesh has" & Open_Edges (Mesh)'Image & " open edges");
      Assert
        (Misoriented_Edges (Mesh) = 0,
         "the triangles do not all turn the same way");
   end Mesh_Is_Welded_And_Closed;

   procedure Unscaled_Without_Dimensions (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Assert_Size
        (Written ("plain"), 6.0, 4.0, Relief_Height + Base, "no dimensions");
   end Unscaled_Without_Dimensions;

   procedure Every_Given_Axis_Is_Exact (T : in out Test_Case) is
      pragma Unreferenced (T);
   begin
      Assert_Size
        (Written ("exact", 100.0, 50.0, 1.5), 100.0, 50.0, 1.5, "100x50x1.5");
   end Every_Given_Axis_Is_Exact;

   --  A width or height left at 0 follows the other one; a depth left at 0
   --  keeps the relief height in millimetres.
   procedure Free_Axes (T : in out Test_Case) is
      pragma Unreferenced (T);
      Thickness : constant Float := Relief_Height + Base;
   begin
      Assert_Size
        (Written ("width", Width => 120.0), 120.0, 80.0, Thickness, "120x0x0");
      Assert_Size
        (Written ("height", Height => 20.0), 30.0, 20.0, Thickness, "0x20x0");
      Assert_Size
        (Written ("both", 60.0, 60.0), 60.0, 60.0, Thickness, "60x60x0");
      Assert_Size
        (Written ("depth", Width => 12.0, Depth => 4.0),
         12.0,
         8.0,
         4.0,
         "12x0x4");
   end Free_Axes;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Package_Layout'Access, "ZIP/OPC package layout");
      Register_Routine
        (T, Mesh_Is_Welded_And_Closed'Access, "the mesh is welded and closed");
      Register_Routine
        (T,
         Unscaled_Without_Dimensions'Access,
         "without dimensions the mesh is centred but not scaled");
      Register_Routine
        (T,
         Every_Given_Axis_Is_Exact'Access,
         "every axis given in dimensions is scaled exactly");
      Register_Routine
        (T, Free_Axes'Access, "axes left at 0 in dimensions");
   end Register_Tests;

end File3mf_Tests;
