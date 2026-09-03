------------------------------------------------------------------------------
--  lithophane.adb
--
--  Root package body. Contains:
--    * Parse_Config -- load the TOML file named by Settings.config and
--      override the matching Settings fields, reporting errors on stderr;
--    * Print_Matrix -- dump a colour matrix as text;
--    * Calculate_Facets -- turn the filtered height map into a watertight
--      triangle mesh (relief surface, base and side walls);
--    * Calculate_Normal -- unit normal of a triangle from its three points.
--
--  Created : 2026-08-23
--  Author  : Simon Beàn
------------------------------------------------------------------------------

with TOML;
with TOML.File_IO;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

package body Lithophane is

   Width    : constant Float := -1.0;
   Reductor : constant Float := 100.0;

   procedure Print_Matrix
     (the_matrix : Matrix_Access; F : Ada.Text_IO.File_Type := Standard_Output)
   is
   begin
      for i in the_matrix.all'Range (1) loop
         for j in the_matrix.all'Range (2) loop
            Put (F, the_matrix (i, j)'Img & " ");
         end loop;
         New_Line (F);
      end loop;
   end Print_Matrix;

   procedure Parse_Config (Settings : in out Settings_Record) is
      use Ada.Strings.Unbounded;
      use type TOML.Any_Value_Kind;
      use type TOML.Any_Integer;

      Config_Name : constant String := To_String (Settings.config);
      Result      : constant TOML.Read_Result :=
        TOML.File_IO.Load_File (Config_Name);

      Table : TOML.TOML_Value;

      --  Return the entry for Key if it is present and has the Expected kind,
      --  and No_TOML_Value otherwise.
      function Field
        (Key : String; Expected : TOML.Any_Value_Kind) return TOML.TOML_Value
      is
      begin
         if Table.Has (Key) and then Table.Get (Key).Kind = Expected then
            return Table.Get (Key);
         else
            return TOML.No_TOML_Value;
         end if;
      end Field;

   begin
      if not Result.Success then
         Put_Line
           (Standard_Error,
            "error while loading config file " & Config_Name & ":");
         Put_Line (Standard_Error, TOML.Format_Error (Result));
         return;
      end if;

      Table := Result.Value;

      if Table.Kind /= TOML.TOML_Table then
         Put_Line
           (Standard_Error,
            "invalid config file "
            & Config_Name
            & ": top-level value must be a table");
         return;
      end if;

      declare
         V : TOML.TOML_Value;
      begin
         V := Field ("input-name", TOML.TOML_String);
         if V.Is_Present then
            Settings.filename := TOML.As_Unbounded_String (V);
         end if;

         V := Field ("output-name", TOML.TOML_String);
         if V.Is_Present then
            Settings.outfilename := TOML.As_Unbounded_String (V);
         end if;

         V := Field ("height", TOML.TOML_Integer);
         if V.Is_Present and then TOML.As_Integer (V) >= 0 then
            Settings.height := Natural (TOML.As_Integer (V));
         end if;

         V := Field ("border_size", TOML.TOML_Integer);
         if V.Is_Present and then TOML.As_Integer (V) >= 0 then
            Settings.border := Natural (TOML.As_Integer (V));
         end if;

         V := Field ("save-binary", TOML.TOML_Boolean);
         if V.Is_Present then
            Settings.save_as_binary := TOML.As_Boolean (V);
         end if;

         V := Field ("save-ascii", TOML.TOML_Boolean);
         if V.Is_Present then
            Settings.save_as_ascii := TOML.As_Boolean (V);
         end if;

         V := Field ("save-3mf", TOML.TOML_Boolean);
         if V.Is_Present then
            Settings.save_as_3mf := TOML.As_Boolean (V);
         end if;

         V := Field ("save-pgm", TOML.TOML_Boolean);
         if V.Is_Present then
            Settings.save_pgm := TOML.As_Boolean (V);
         end if;

         V := Field ("filter", TOML.TOML_String);
         if V.Is_Present then
            Settings.filter :=
              Lithophane.Filters_Choice'Value (TOML.As_String (V));
         end if;

         V := Field ("filter_size", TOML.TOML_Integer);
         if V.Is_Present
           and then TOML.As_Integer (V) >= 0
           and then TOML.As_Integer (V) mod 2 = 1
         then
            Settings.filter_size := Natural (TOML.As_Integer (V));
         end if;

         V := Field ("filter_threshold", TOML.TOML_Integer);
         if V.Is_Present
           and then TOML.As_Integer (V) >= 0
           and then TOML.As_Integer (V) <= 255
         then
            Settings.filter_threshold := Color_Type (TOML.As_Integer (V));
         end if;

         V := Field ("border_size", TOML.TOML_Integer);
         if V.Is_Present and then TOML.As_Integer (V) >= 0 then
            Settings.border := Natural (TOML.As_Integer (V));
         end if;

         --  dimensions = { width = <mm>, height = <mm>, depth = <mm> }
         --  Every sub-key is optional; a missing or non-numeric one keeps
         --  its 0.0 default (meaning "unconstrained on that axis").
         declare
            D : constant TOML.TOML_Value :=
              Field ("dimensions", TOML.TOML_Table);

            function Dim (Key : String) return Float is
            begin
               if not D.Has (Key) then
                  return 0.0;
               elsif D.Get (Key).Kind = TOML.TOML_Float then
                  return Float (TOML.As_Float (D.Get (Key)).Value);
               elsif D.Get (Key).Kind = TOML.TOML_Integer then
                  return Float (TOML.As_Integer (D.Get (Key)));
               else
                  return 0.0;
               end if;
            end Dim;
         begin
            if D.Is_Present then
               Settings.dimensions :=
                 (width  => Dim ("width"),
                  height => Dim ("height"),
                  depth  => Dim ("depth"));
            end if;
         end;

      end;

      Put_Line (Config_Name & " loaded with success!");
   end Parse_Config;

   function Calculate_Normal (P0 : Point; P1 : Point; P2 : Point) return Vector
   is
      VX    : Float := 0.0;
      VY    : Float := 0.0;
      VZ    : Float := 0.0;
      Norme : Float := 0.0;
      V     : Vector;
   begin
      VX :=
        ((P1.py - P0.py) * (P2.pz - P0.pz))
        - ((P1.pz - P0.pz) * (P2.py - P0.py));
      VY :=
        ((P1.pz - P0.pz) * (P2.px - P0.px))
        - ((P1.px - P0.px) * (P2.pz - P0.pz));
      VZ :=
        ((P1.px - P0.px) * (P2.py - P0.py))
        - ((P2.px - P0.px) * (P1.py - P0.py));
      Norme := Sqrt (VX ** 2 + VY ** 2 + VZ ** 2);

      if Norme > 0.0 then
         V.vx := VX / Norme;
         V.vy := VY / Norme;
         V.vz := VZ / Norme;
      end if;
      return V;
   end Calculate_Normal;

   function Calculate_Facets (the_matrix : Matrix_Access) return Facets.Vector
   is
      Facets_List : Facets.Vector;

      First_I : constant Natural := the_matrix.all'First (1);
      Last_I  : constant Natural := the_matrix.all'Last (1);
      First_J : constant Natural := the_matrix.all'First (2);
      Last_J  : constant Natural := the_matrix.all'Last (2);

      --  Marks top-surface cells already emitted as part of a merged
      --  flat rectangle, so they are not triangulated a second time.
      type Done_Matrix is
        array (Natural range <>, Natural range <>) of Boolean;
      type Done_Access is access Done_Matrix;

      Done : constant Done_Access :=
        new Done_Matrix (First_I .. Last_I - 1, First_J .. Last_J - 1);

      A_Facet : Facet;

      --  A cell is flat when its four corners sit at the same height:
      --  it can then be merged with its flat neighbours instead of
      --  producing its own pair of triangles.
      function Is_Flat_Cell (I, J : Natural) return Boolean is
         H : constant Color_Type := the_matrix (I, J);
      begin
         return
           the_matrix (I + 1, J) = H
           and then the_matrix (I, J + 1) = H
           and then the_matrix (I + 1, J + 1) = H;
      end Is_Flat_Cell;

      procedure Emit_ABC (A, B, C : Point) is
      begin
         A_Facet.Vertex_A := A;
         A_Facet.Vertex_B := B;
         A_Facet.Vertex_C := C;
         A_Facet.Normal := Calculate_Normal (A, B, C);
         Facets_List.Append (A_Facet);
      end Emit_ABC;

      procedure Emit_ACB (A, B, C : Point) is
      begin
         A_Facet.Vertex_A := A;
         A_Facet.Vertex_B := B;
         A_Facet.Vertex_C := C;
         A_Facet.Normal := Calculate_Normal (A, C, B);
         Facets_List.Append (A_Facet);
      end Emit_ACB;

      --  Triangulates a flat rectangle [Ix0..Ix1] x [Jy0..Jy1], visiting
      --  every unit-spaced point along its four edges rather than just
      --  the four corners. This keeps the merged region conformal with
      --  whatever unmerged, per-pixel geometry may sit right next to it
      --  (walls, sloped cells, other merged rectangles): every point a
      --  neighbour could possibly reference is already a vertex here,
      --  so no edge is ever shared by more or less than two triangles.
      --  For a single unit cell (no actual merge) this is just the
      --  original two triangles. Otherwise every boundary point is
      --  connected to the rectangle's centre rather than to one of its
      --  own corners, so no triangle ever degenerates to zero area
      --  (a corner-based fan would, along its two incident edges).
      procedure Emit_Flat_Rect_Fan
        (Ix0, Ix1, Jy0, Jy1 : Natural; Z : Float; Clockwise : Boolean) is
      begin
         if Ix1 = Ix0 + 1 and then Jy1 = Jy0 + 1 then
            declare
               P00 : constant Point := (Float (Ix0), Float (Jy0), Z);
               P10 : constant Point := (Float (Ix1), Float (Jy0), Z);
               P01 : constant Point := (Float (Ix0), Float (Jy1), Z);
               P11 : constant Point := (Float (Ix1), Float (Jy1), Z);
            begin
               if Clockwise then
                  Emit_ABC (P00, P01, P10);
                  Emit_ABC (P10, P01, P11);
               else
                  Emit_ABC (P00, P10, P01);
                  Emit_ABC (P10, P11, P01);
               end if;
            end;
            return;
         end if;

         declare
            C           : constant Point :=
              (Float (Ix0 + Ix1) / 2.0, Float (Jy0 + Jy1) / 2.0, Z);
            First_Point : Point;
            Prev        : Point;
            Started     : Boolean := False;

            procedure Visit (P : Point) is
            begin
               if not Started then
                  First_Point := P;
                  Prev := P;
                  Started := True;
               else
                  if Clockwise then
                     Emit_ABC (C, Prev, P);
                  else
                     Emit_ABC (C, P, Prev);
                  end if;
                  Prev := P;
               end if;
            end Visit;
         begin
            for J in Jy0 .. Jy1 - 1 loop
               --  left side
               Visit ((Float (Ix0), Float (J), Z));
            end loop;
            for I in Ix0 .. Ix1 - 1 loop
               --  top side
               Visit ((Float (I), Float (Jy1), Z));
            end loop;
            for J in reverse Jy0 + 1 .. Jy1 loop
               --  right side
               Visit ((Float (Ix1), Float (J), Z));
            end loop;
            for I in reverse Ix0 + 1 .. Ix1 loop
               --  bottom side
               Visit ((Float (I), Float (Jy0), Z));
            end loop;
            Visit (First_Point);                       --  closes the loop
         end;
      end Emit_Flat_Rect_Fan;

   begin
      Done.all := [others => [others => False]];

      --  The bottom is always flat across the whole grid: a single fan
      --  is enough for the entire perimeter, instead of a pair of
      --  triangles per pixel.
      if Last_I > First_I and then Last_J > First_J then
         Emit_Flat_Rect_Fan
           (First_I, Last_I, First_J, Last_J, Width, Clockwise => True);
      end if;

      for I in First_I .. Last_I - 1 loop
         for J in First_J .. Last_J - 1 loop

            declare
               P00 : constant Point :=
                 (Float (I), Float (J), Float (the_matrix (I, J)) / Reductor);
               P10 : constant Point :=
                 (Float (I + 1),
                  Float (J),
                  Float (the_matrix (I + 1, J)) / Reductor);
               P01 : constant Point :=
                 (Float (I),
                  Float (J + 1),
                  Float (the_matrix (I, J + 1)) / Reductor);
               P11 : constant Point :=
                 (Float (I + 1),
                  Float (J + 1),
                  Float (the_matrix (I + 1, J + 1)) / Reductor);
            begin

               --  Surface: merges neighbouring flat cells into a single
               --  rectangle (greedy meshing), otherwise falls back to the
               --  original per-pixel triangulation, geometry unchanged.
               if not Done (I, J) then
                  if Is_Flat_Cell (I, J) then
                     declare
                        H      : constant Color_Type := the_matrix (I, J);
                        Zf     : constant Float := Float (H) / Reductor;
                        W      : Natural := 1;
                        Ht     : Natural := 1;
                        Row_OK : Boolean;
                     begin
                        while I + W <= Last_I - 1
                          and then not Done (I + W, J)
                          and then Is_Flat_Cell (I + W, J)
                          and then the_matrix (I + W, J) = H
                        loop
                           W := W + 1;
                        end loop;

                        Grow_Height : loop
                           exit Grow_Height when J + Ht > Last_J - 1;
                           Row_OK := True;
                           for K in I .. I + W - 1 loop
                              if Done (K, J + Ht)
                                or else not Is_Flat_Cell (K, J + Ht)
                                or else the_matrix (K, J + Ht) /= H
                              then
                                 Row_OK := False;
                                 exit;
                              end if;
                           end loop;
                           exit Grow_Height when not Row_OK;
                           Ht := Ht + 1;
                        end loop Grow_Height;

                        for A_Idx in I .. I + W - 1 loop
                           for B_Idx in J .. J + Ht - 1 loop
                              Done (A_Idx, B_Idx) := True;
                           end loop;
                        end loop;

                        Emit_Flat_Rect_Fan
                          (I, I + W, J, J + Ht, Zf, Clockwise => False);
                     end;
                  else
                     Emit_ABC (P00, P10, P01);
                     Emit_ABC (P10, P11, P01);
                     Done (I, J) := True;
                  end if;
               end if;

               --  Sides: always per unit cell. The perimeter does not
               --  benefit from merging but stays cheap (proportional to
               --  the perimeter, not the surface) and must stay at
               --  pixel resolution to exactly connect the bottom and
               --  the surface, whether merged or not.
               if I = First_I then
                  Emit_ACB
                    (P00,
                     (Float (I), Float (J + 1), Width),
                     (Float (I), Float (J), Width));
                  Emit_ACB (P00, P01, (Float (I), Float (J + 1), Width));
               end if;

               if J = First_J then
                  Emit_ACB
                    (P00,
                     (Float (I), Float (J), Width),
                     (Float (I + 1), Float (J), Width));
                  Emit_ACB (P00, (Float (I + 1), Float (J), Width), P10);
               end if;

               if I + 1 = Last_I then
                  Emit_ACB
                    (P10,
                     (Float (I + 1), Float (J), Width),
                     (Float (I + 1), Float (J + 1), Width));
                  Emit_ABC (P10, (Float (I + 1), Float (J + 1), Width), P11);
               end if;

               if J + 1 = Last_J then
                  Emit_ABC
                    (P01,
                     (Float (I + 1), Float (J + 1), Width),
                     (Float (I), Float (J + 1), Width));
                  Emit_ACB (P01, P11, (Float (I + 1), Float (J + 1), Width));
               end if;
            end;

         end loop;
      end loop;
      return Facets_List;
   end Calculate_Facets;

end Lithophane;
