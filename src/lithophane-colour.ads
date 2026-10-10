------------------------------------------------------------------------------
--  lithophane-colour.ads
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Specification of Lithophane.Colour: the colour lithophane, a stack of
--  five solids to print with four filaments. Seen from the flat back:
--    * a thin white sheet, the first layers on the bed;
--    * a cyan, a magenta and a yellow layer, each as thick at a pixel as
--      the picture holds of that ink there (nothing where it holds none);
--    * the white lithophane itself, base and relief, lying on top of them.
--  The three inks give the hue (they filter the light going through), the
--  white relief gives the darkness, as in a plain lithophane.
--
--  The picture is split the CMYK way: the height map is the black (K)
--  component, 1.0 - max (R, G, B), and the inks are what is left of each
--  channel once that black is taken out.
--
--  Created : 2026-10-07
--  Author  : Simon Beàn & Claude Code
------------------------------------------------------------------------------

with Lithophane.File3mf;

package Lithophane.Colour is

   type Ink is (Cyan, Magenta, Yellow);

   --  How much of each ink a pixel holds, from 0.0 (none) to 1.0: one
   --  matrix per ink, with the bounds of the height map.
   type Ink_Maps is array (Ink) of Matrix_Grey_Access;

   type Ink_Values is array (Ink) of Grey_Type;

   --  Thickness, in millimetres, of an ink layer where the ink is 1.0.
   Ink_Thickness : constant Float := 0.4;

   --  An ink below this level is left out of the mesh: the layer would be
   --  far thinner than anything a printer can lay down.
   Min_Ink : constant Grey_Type := 0.01;

   --  Split a pixel into its inks and its black component. Black itself
   --  holds no ink: the white relief alone makes it dark.
   procedure To_CMYK
     (Red, Green, Blue : Color_Type;
      Inks             : out Ink_Values;
      Black            : out Grey_Type);

   --  Thickness, in millimetres, of the white sheet printed under the inks:
   --  two layers of 0.1 mm.
   Back_Thickness : constant Float := 0.2;

   --  The parts of the model, from the back to the front.
   Back_Part    : constant := 1;
   Cyan_Part    : constant := 2;
   Magenta_Part : constant := 3;
   Yellow_Part  : constant := 4;
   White_Part   : constant := 5;

   subtype Layer_Parts is File3mf.Model_Parts (Back_Part .. White_Part);

   --  The filament of each part in the slicer; both white parts share one.
   Cyan_Filament    : constant := 1;
   Magenta_Filament : constant := 2;
   Yellow_Filament  : constant := 3;
   White_Filament   : constant := 4;

   --  Build the five solids from the height map the_matrix and the inks.
   --  Each one is closed; an ink layer exists only where its ink does, and
   --  is left empty when the picture holds none of it at all. Where an ink
   --  vanishes along the edge between two pixels while it is present on
   --  both sides, its layer would be pinched to nothing there, and that
   --  edge would bound four triangles instead of two: one end of such an
   --  edge is given Min_Ink, so every edge bounds two triangles.
   --
   --  X and Y are in pixels, as in Calculate_Facets. Z is in millimetres,
   --  from 0.0 at the back: the white sheet (Back_Thickness), the ink
   --  layers (Ink_Thickness each at most), then the white part,
   --  Base_Thickness plus a relief of at most Settings.height. A depth in Settings.dimensions is the thickness of
   --  that white part and is applied here; the sheet and the ink layers
   --  come on top of it and keep their thickness.
   procedure Calculate_Layers
     (the_matrix : Matrix_Grey_Access;
      Inks       : Ink_Maps;
      Settings   : Settings_Record;
      Parts      : in out Layer_Parts);

   --  Write the colour lithophane as "<Settings.outfilename>.3mf": one
   --  object made of the white sheet and the cyan, magenta, yellow and
   --  white parts. The width
   --  and height of Settings.dimensions scale X and Y as in
   --  File3mf.Dump_3mf.
   procedure Dump_Colour_3mf
     (the_matrix : Matrix_Grey_Access;
      Inks       : Ink_Maps;
      Settings   : Settings_Record);

end Lithophane.Colour;
