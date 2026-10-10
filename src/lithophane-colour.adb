------------------------------------------------------------------------------
--  lithophane-colour.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Body of Lithophane.Colour. Contains:
--    * To_CMYK -- split an RGB pixel into cyan, magenta, yellow and black;
--    * Calculate_Layers -- the model is cut by six surfaces stacked over
--      the pixel grid (the flat back, the top of the white sheet and of
--      each ink layer, the relief); every part is the solid held between
--      two consecutive ones, so two neighbouring parts meet exactly,
--      without gap nor overlap;
--    * Dump_Colour_3mf -- build the parts and write them as one 3MF file.
--
--  Created : 2026-10-07
--  Author  : Simon Beàn & Claude Code
------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;

package body Lithophane.Colour is

   procedure To_CMYK
     (Red, Green, Blue : Color_Type;
      Inks             : out Ink_Values;
      Black            : out Grey_Type)
   is
      Brightest : constant Color_Type :=
        Color_Type'Max (Red, Color_Type'Max (Green, Blue));

      function Ink_Of (Channel : Color_Type) return Grey_Type
      is (Grey_Type (Float (Brightest - Channel) / Float (Brightest)));
   begin
      Black := Grey_Type (1.0 - Float (Brightest) / 255.0);
      if Brightest = 0 then
         Inks := [others => 0.0];
      else
         Inks :=
           [Cyan    => Ink_Of (Red),
            Magenta => Ink_Of (Green),
            Yellow  => Ink_Of (Blue)];
      end if;
   end To_CMYK;

   procedure Calculate_Layers
     (the_matrix : Matrix_Grey_Access;
      Inks       : Ink_Maps;
      Settings   : Settings_Record;
      Parts      : in out Layer_Parts)
   is
      First_I : constant Natural := the_matrix.all'First (1);
      Last_I  : constant Natural := the_matrix.all'Last (1);
      First_J : constant Natural := the_matrix.all'First (2);
      Last_J  : constant Natural := the_matrix.all'Last (2);

      --  Relief scale, as in Calculate_Facets: the brightest grey is raised
      --  to Settings.height.
      Scale : Float := 0.0;

      --  Z scale of the white part: 1.0 unless a depth is requested, which
      --  is then the thickness of the base and the highest point together.
      White_Scale : Float := 1.0;

      --  The surfaces cutting the model, from the back to the front: the
      --  flat back, the top of the white sheet and of the cyan, magenta and
      --  yellow layers, and the relief. The part N lies between the
      --  surfaces N - 1 and N.
      subtype Surface is Natural range 0 .. White_Part;

      --  The ink levels the layers are built from: those of Inks, without
      --  the ones too low to be printed and without pinched edges.
      Levels : Ink_Maps;

      procedure Free is new
        Ada.Unchecked_Deallocation (Matrix_Grey_Type, Matrix_Grey_Access);

      --  An edge of the mesh without ink at both ends, between two
      --  triangles that both hold some, would bound the top and the bottom
      --  of the layer on each side: four triangles, which is not a
      --  manifold. A trace of ink at one of its ends opens the layer there.
      --  This may pinch another edge next to it, hence the loop; it only
      --  ever fills gaps one edge wide.
      procedure Open_Pinched_Edges (Map : in out Matrix_Grey_Type) is
         Changed : Boolean;

         function Inked (I, J : Integer) return Boolean
         is (I in First_I .. Last_I
             and then J in First_J .. Last_J
             and then Map (I, J) > 0.0);

         --  The edge from (I, J) to (To_I, To_J), the third corner of the
         --  triangle on each side of it being Left and Right.
         procedure Check
           (I, J, To_I, To_J, Left_I, Left_J, Right_I, Right_J : Integer) is
         begin
            if not Inked (I, J)
              and then not Inked (To_I, To_J)
              and then Inked (Left_I, Left_J)
              and then Inked (Right_I, Right_J)
            then
               Map (I, J) := Min_Ink;
               Changed := True;
            end if;
         end Check;
      begin
         loop
            Changed := False;
            for I in First_I .. Last_I loop
               for J in First_J .. Last_J loop
                  --  The three edges of the triangulation that start in
                  --  the cell (I, J): along X, along Y and its diagonal.
                  Check (I, J, I + 1, J, I, J + 1, I + 1, J - 1);
                  Check (I, J, I, J + 1, I + 1, J, I - 1, J + 1);
                  Check (I + 1, J, I, J + 1, I, J, I + 1, J + 1);
               end loop;
            end loop;
            exit when not Changed;
         end loop;
      end Open_Pinched_Edges;

      function Layer (Which : Ink; I, J : Natural) return Float
      is (Ink_Thickness * Float (Levels (Which) (I, J)));

      --  Height of a surface at a pixel. A surface is always computed the
      --  same way, whichever part asks for it: the top of a part and the
      --  bottom of the next one are the very same points.
      function Height (S : Surface; I, J : Natural) return Float is
         Z : Float := 0.0;
      begin
         if S >= Back_Part then
            Z := Z + Back_Thickness;
         end if;
         if S >= Cyan_Part then
            Z := Z + Layer (Cyan, I, J);
         end if;
         if S >= Magenta_Part then
            Z := Z + Layer (Magenta, I, J);
         end if;
         if S >= Yellow_Part then
            Z := Z + Layer (Yellow, I, J);
         end if;
         if S = White_Part then
            Z :=
              Z
              + White_Scale
                * (Base_Thickness + Float (the_matrix (I, J)) * Scale);
         end if;
         return Z;
      end Height;

      type Corner is record
         I, J : Natural;
      end record;

      --  The solid held between the surfaces Lower and Upper. Where they
      --  meet (no ink) there is nothing: no triangle is emitted there, and
      --  around such a hole the top of the layer simply slopes down to its
      --  bottom, so the solid stays closed.
      procedure Build
        (Lower, Upper : Surface; Mesh : in out Facets.Vector)
      is
         function Top (C : Corner) return Point
         is (Float (C.I), Float (C.J), Height (Upper, C.I, C.J));

         function Bottom (C : Corner) return Point
         is (Float (C.I), Float (C.J), Height (Lower, C.I, C.J));

         function Thick (C : Corner) return Boolean
         is (Height (Upper, C.I, C.J) > Height (Lower, C.I, C.J));

         procedure Emit (A, B, C : Point) is
         begin
            Mesh.Append
              (Facet'
                 (Normal   => Calculate_Normal (A, B, C),
                  Vertex_A => A,
                  Vertex_B => B,
                  Vertex_C => C));
         end Emit;

         --  Top and bottom of the solid over the triangle A, B, C, given
         --  counter-clockwise seen from above.
         procedure Cover (A, B, C : Corner) is
         begin
            if Thick (A) or else Thick (B) or else Thick (C) then
               Emit (Top (A), Top (B), Top (C));
               Emit (Bottom (A), Bottom (C), Bottom (B));
            end if;
         end Cover;

         --  Side of the solid along the outline of the grid, from P to Q
         --  with the inside on the left.
         procedure Wall (P, Q : Corner) is
         begin
            if Thick (P) then
               Emit (Top (P), Bottom (P), Bottom (Q));
            end if;
            if Thick (Q) then
               Emit (Top (P), Bottom (Q), Top (Q));
            end if;
         end Wall;
      begin
         Mesh.Clear;
         for I in First_I .. Last_I - 1 loop
            for J in First_J .. Last_J - 1 loop
               Cover ((I, J), (I + 1, J), (I, J + 1));
               Cover ((I + 1, J), (I + 1, J + 1), (I, J + 1));

               if J = First_J then
                  Wall ((I, J), (I + 1, J));
               end if;
               if I + 1 = Last_I then
                  Wall ((I + 1, J), (I + 1, J + 1));
               end if;
               if J + 1 = Last_J then
                  Wall ((I + 1, J + 1), (I, J + 1));
               end if;
               if I = First_I then
                  Wall ((I, J + 1), (I, J));
               end if;
            end loop;
         end loop;
      end Build;

   begin
      for Map of Inks loop
         if Map = null
           or else Map'First (1) /= First_I
           or else Map'Last (1) /= Last_I
           or else Map'First (2) /= First_J
           or else Map'Last (2) /= Last_J
         then
            raise Constraint_Error
              with "the inks and the height map do not have the same size";
         end if;
      end loop;

      declare
         Max_Grey : Grey_Type := 0.0;
         Relief   : Float := 0.0;
      begin
         for I in First_I .. Last_I loop
            for J in First_J .. Last_J loop
               Max_Grey := Grey_Type'Max (Max_Grey, the_matrix (I, J));
            end loop;
         end loop;
         if Max_Grey > 0.0 then
            Scale := Settings.height / Float (Max_Grey);
            Relief := Settings.height;
         end if;
         if Settings.dimensions.depth > 0.0 then
            White_Scale :=
              Settings.dimensions.depth / (Base_Thickness + Relief);
         end if;
      end;

      for Which in Ink loop
         Levels (Which) := new Matrix_Grey_Type'(Inks (Which).all);
         for Level of Levels (Which).all loop
            if Level < Min_Ink then
               Level := 0.0;
            end if;
         end loop;
         Open_Pinched_Edges (Levels (Which).all);
      end loop;

      Parts (Back_Part).Name := To_Unbounded_String ("white back");
      Parts (Back_Part).Colour := "#FFFFFF";
      Parts (Back_Part).Filament := White_Filament;
      Parts (Cyan_Part).Name := To_Unbounded_String ("cyan");
      Parts (Cyan_Part).Colour := "#00FFFF";
      Parts (Cyan_Part).Filament := Cyan_Filament;
      Parts (Magenta_Part).Name := To_Unbounded_String ("magenta");
      Parts (Magenta_Part).Colour := "#FF00FF";
      Parts (Magenta_Part).Filament := Magenta_Filament;
      Parts (Yellow_Part).Name := To_Unbounded_String ("yellow");
      Parts (Yellow_Part).Colour := "#FFFF00";
      Parts (Yellow_Part).Filament := Yellow_Filament;
      Parts (White_Part).Name := To_Unbounded_String ("white");
      Parts (White_Part).Colour := "#FFFFFF";
      Parts (White_Part).Filament := White_Filament;

      for N in Parts'Range loop
         Build (Lower => N - 1, Upper => N, Mesh => Parts (N).Mesh);
      end loop;

      for Map of Levels loop
         Free (Map);
      end loop;
   end Calculate_Layers;

   procedure Dump_Colour_3mf
     (the_matrix : Matrix_Grey_Access;
      Inks       : Ink_Maps;
      Settings   : Settings_Record)
   is
      Parts : Layer_Parts;

      --  The depth is already applied by Calculate_Layers, to the white
      --  part only: Z is left alone by the writer.
      Unscaled_Z : Settings_Record := Settings;
   begin
      Calculate_Layers (the_matrix, Inks, Settings, Parts);
      Unscaled_Z.dimensions.depth := 0.0;
      File3mf.Dump_3mf (Parts, Unscaled_Z);
   end Dump_Colour_3mf;

end Lithophane.Colour;
