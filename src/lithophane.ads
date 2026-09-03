------------------------------------------------------------------------------
--  lithophane.ads
--
--  Root package specification for the lithophane generator. Declares the
--  shared vocabulary used across the whole program:
--    * scalar types: Color_Type (0 .. 255), Grey_Type (0.0 .. 1.0);
--    * Dimensions_Type, the optional target physical size in millimetres;
--    * Settings_Record, holding every run option (filter, border, output
--      formats, file names, config path, dimensions);
--    * geometry types Vector / Point / Facet and the Facets vector;
--    * image containers (Matrix_Type, Matrix_Grey_Type and their accesses)
--      and Matrix_Filter_Type for convolution kernels.
--  It also declares Parse_Config (TOML overrides), Calculate_Facets
--  (height map -> triangle mesh), Calculate_Normal and Print_Matrix.
--
--  Created : 2026-08-23
--  Author  : Simon Beàn
------------------------------------------------------------------------------

with Ada.Containers.Vectors;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded;

package Lithophane is
   pragma Elaborate_Body;

   type Filters_Choice is (bartlett, gauss, square, sharpen, threshold);

   type Color_Type is new Integer range 0 .. 255;
   type Grey_Type is new Float range 0.0 .. 1.0;

   --  Target physical size of the model, in millimetres, applied when a 3MF
   --  file is written (3MF geometry is unit-aware, STL is not). A value of
   --  0.0 on an axis means "do not constrain that axis": its scale is then
   --  inherited from whichever axis is set, so the model keeps its natural
   --  proportions. If every axis is 0.0 the mesh is written unscaled.
   type Dimensions_Type is record
      width  : Float := 0.0;   --  X extent
      height : Float := 0.0;   --  Y extent
      depth  : Float := 0.0;   --  Z extent (total thickness: base + relief)
   end record;

   type Settings_Record is record
      height           : Natural := 0;
      border           : Natural := 20;
      filter           : Filters_Choice := threshold;
      filter_size      : Natural := 3;
      filter_threshold : Color_Type := 128;
      save_as_binary   : Boolean := True;
      save_as_ascii    : Boolean := False;
      save_as_3mf      : Boolean := False;
      save_pgm         : Boolean := False;
      dimensions       : Dimensions_Type := (others => 0.0);
      filename         : Ada.Strings.Unbounded.Unbounded_String;
      outfilename      : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String ("test");
      config           : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Vector is record
      vx : Float := 0.0;
      vy : Float := 0.0;
      vz : Float := 0.0;
   end record;

   type Point is record
      px : Float := 0.0;
      py : Float := 0.0;
      pz : Float := 0.0;
   end record;

   type Facet is record
      Normal   : Vector;
      Vertex_A : Point;
      Vertex_B : Point;
      Vertex_C : Point;
   end record;

   package Facets is new
     Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Facet);

   type Matrix_Type is
     array (Natural range <>, Natural range <>) of Color_Type;

   type Matrix_Grey_Type is
     array (Natural range <>, Natural range <>) of Grey_Type;

   type Matrix_Access is access Matrix_Type;
   type Matrix_Grey_Access is access Matrix_Grey_Type;

   type Matrix_Filter_Type is
     array (Positive range <>, Positive range <>) of Integer;
   --  Filter weights may be negative (e.g. the sharpen kernel).

   procedure Print_Matrix
     (the_matrix : Matrix_Access;
      F          : Ada.Text_IO.File_Type := Standard_Output);

   procedure Parse_Config (Settings : in out Settings_Record);
   --  Read the TOML file named by Settings.config and override the matching
   --  fields of Settings with the values it contains. On error, a diagnostic
   --  is printed on Standard_Error and Settings is left unchanged.

   function Calculate_Facets (the_matrix : Matrix_Access) return Facets.Vector;

   function Calculate_Normal
     (P0 : Point; P1 : Point; P2 : Point) return Vector;

end Lithophane;
