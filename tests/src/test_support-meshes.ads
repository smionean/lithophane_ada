------------------------------------------------------------------------------
--  test_support-meshes.ads
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Read back the meshes written by the program (binary STL, 3MF) and
--  measure them: bounding box, open edges, degenerate triangles.
------------------------------------------------------------------------------

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Interfaces;

package Test_Support.Meshes is

   type Box is record
      Min : Point := (others => Float'Last);
      Max : Point := (others => Float'First);
   end record;

   function Bounding_Box (Mesh : Facets.Vector) return Box;

   --  Number of edges that are not shared by exactly two triangles; 0 for a
   --  closed (watertight) mesh. Vertices are matched by position.
   function Open_Edges (Mesh : Facets.Vector) return Natural;

   --  Number of edges followed in the same direction by two triangles; 0
   --  when the triangles of a closed mesh all turn the same way.
   function Misoriented_Edges (Mesh : Facets.Vector) return Natural;

   --  Number of triangles with a null area.
   function Degenerate_Facets (Mesh : Facets.Vector) return Natural;

   --  True when a vertex of Mesh lies at (X, Y, Z).
   function Has_Vertex (Mesh : Facets.Vector; X, Y, Z : Float) return Boolean;

   function Read_Binary_STL (Path : String) return Facets.Vector;

   --  The parts of a ZIP archive written with the "stored" method.
   type Zip_Part is record
      Name : Ada.Strings.Unbounded.Unbounded_String;
      Data : Ada.Strings.Unbounded.Unbounded_String;
      CRC  : Interfaces.Unsigned_32;   --  as recorded in the archive
   end record;

   package Zip_Part_Vectors is new
     Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Zip_Part);

   function Read_Zip (Path : String) return Zip_Part_Vectors.Vector;

   function CRC_32 (Data : String) return Interfaces.Unsigned_32;

   --  The mesh of a 3MF model part: shared vertices and triangles made of
   --  0-based vertex indices.
   package Point_Vectors is new
     Ada.Containers.Vectors (Index_Type => Natural, Element_Type => Point);

   type Triangle is record
      V1, V2, V3 : Natural;
   end record;

   package Triangle_Vectors is new
     Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Triangle);

   type Model is record
      Vertices  : Point_Vectors.Vector;
      Triangles : Triangle_Vectors.Vector;
   end record;

   --  The mesh held by the 3D/3dmodel.model part of the 3MF file Path.
   function Read_3MF (Path : String) return Model;

   function Bounding_Box (Mesh : Model) return Box;

   --  Same as above, vertices being matched by index: 0 only if the
   --  coincident vertices have been welded.
   function Open_Edges (Mesh : Model) return Natural;
   function Misoriented_Edges (Mesh : Model) return Natural;

end Test_Support.Meshes;
