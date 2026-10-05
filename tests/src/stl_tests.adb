------------------------------------------------------------------------------
--  stl_tests.adb
--
--  Regression tests for Lithophane.STL: layout of the binary and ASCII STL
--  files.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Lithophane;          use Lithophane;
with Lithophane.STL;      use Lithophane.STL;
with Test_Support;        use Test_Support;
with Test_Support.Meshes; use Test_Support.Meshes;

package body STL_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   function Sample return Facets.Vector is
      Image : constant Matrix_Grey_Access := Flat_Matrix (4, 3, 0.25);
   begin
      Image (2, 2) := 1.0;
      return Calculate_Facets (Image, (height => 6.0, others => <>));
   end Sample;

   function Named (Name : String) return Settings_Record
   is (outfilename =>
         Ada.Strings.Unbounded.To_Unbounded_String (Scratch (Name)),
       others      => <>);

   procedure Binary_Layout (T : in out Test_Case) is
      pragma Unreferenced (T);
      Mesh : constant Facets.Vector := Sample;
      File : constant String := Scratch ("layout.bin.stl");
   begin
      Reset_Scratch;
      Dump_STL_BIN (Mesh, Named ("layout"));
      Assert (Exists (File), File & " was not written");

      declare
         Content : constant String := Read_File (File);
         Count   : constant Natural :=
           Character'Pos (Content (81))
           + 256 * Character'Pos (Content (82))
           + 65_536 * Character'Pos (Content (83));
      begin
         --  80 bytes of header, the number of triangles on 4 bytes
         --  (little-endian), then 50 bytes per triangle.
         Assert
           (Content'Length = 84 + 50 * Natural (Mesh.Length),
            "wrong file size:" & Content'Length'Image);
         Assert
           (Count = Natural (Mesh.Length) and then Content (84) = ASCII.NUL,
            "wrong number of triangles:" & Count'Image);
         Assert
           (Content (1 .. 5) /= "solid",
            "a binary STL must not start with ""solid""");
      end;
   end Binary_Layout;

   procedure Binary_Round_Trip (T : in out Test_Case) is
      pragma Unreferenced (T);
      Mesh : constant Facets.Vector := Sample;
   begin
      Reset_Scratch;
      Dump_STL_BIN (Mesh, Named ("trip"));
      Assert
        (Facets."=" (Read_Binary_STL (Scratch ("trip.bin.stl")), Mesh),
         "the facets read back differ from the ones written");
   end Binary_Round_Trip;

   procedure ASCII_Layout (T : in out Test_Case) is
      pragma Unreferenced (T);
      Mesh : constant Facets.Vector := Sample;
      File : constant String := Scratch ("layout.ascii.stl");
   begin
      Reset_Scratch;
      Dump_STL_ASCII (Mesh, Named ("layout"));
      Assert (Exists (File), File & " was not written");

      declare
         Content : constant String := Without_CR (Read_File (File));
         First   : constant String := "solid lithophane" & ASCII.LF;
         Last    : constant String := "endsolid lithophane" & ASCII.LF;
         Count   : constant Natural := Natural (Mesh.Length);
      begin
         Assert
           (Content (1 .. First'Length) = First,
            "the file does not start with ""solid lithophane""");
         Assert
           (Content (Content'Last - Last'Length + 1 .. Content'Last) = Last,
            "the file does not end with ""endsolid lithophane""");
         Assert
           (Occurrences (Content, "  facet normal ") = Count
            and then Occurrences (Content, "    outer loop") = Count
            and then Occurrences (Content, "      vertex ") = 3 * Count
            and then Occurrences (Content, "    endloop") = Count
            and then Occurrences (Content, "  endfacet") = Count,
            "expected" & Count'Image & " facets of 3 vertices");
      end;
   end ASCII_Layout;

   procedure Empty_Mesh (T : in out Test_Case) is
      pragma Unreferenced (T);
      Nothing : Facets.Vector;
   begin
      Reset_Scratch;
      Dump_STL_BIN (Nothing, Named ("empty"));
      Dump_STL_ASCII (Nothing, Named ("empty"));
      Assert
        (Read_File (Scratch ("empty.bin.stl"))'Length = 84,
         "an empty binary STL is 84 bytes long");
      Assert
        (Occurrences (Read_File (Scratch ("empty.ascii.stl")), "facet") = 0,
         "an empty ASCII STL has no facet");
   end Empty_Mesh;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Binary_Layout'Access, "binary STL layout");
      Register_Routine
        (T, Binary_Round_Trip'Access, "binary STL holds the facets");
      Register_Routine (T, ASCII_Layout'Access, "ASCII STL layout");
      Register_Routine (T, Empty_Mesh'Access, "STL of an empty mesh");
   end Register_Tests;

end STL_Tests;
