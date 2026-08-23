with Ada.Streams.Stream_IO;             use Ada.Streams.Stream_IO;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
--  with Ada.Text_IO;           use Ada.Text_IO;

package body Lithophane.STL is

   Width    : constant Float := -2.0;
   Reductor : constant Float := 100.0;

   procedure Dump_STL_ASCII
     (Facets_List : Facets.Vector; Settings : Settings_Record)
   is
      F : Ada.Text_IO.File_Type;
   begin
      Create
        (F,
         Out_File,
         Ada.Strings.Unbounded.To_String (Settings.outfilename)
         & ".ascii.stl");
      Put_Line (F, "solid lithophane");
      for i in Facets_List.First_Index .. Facets_List.Last_Index loop
         Put_Line
           (F,
            "  facet normal "
            & Facets_List.Element (i).Normal.vx'Img
            & " "
            & Facets_List.Element (i).Normal.vy'Img
            & " "
            & Facets_List.Element (i).Normal.vz'Img);
         Put_Line (F, "    outer loop");
         Put_Line
           (F,
            "      vertex "
            & Facets_List.Element (i).Vertex_A.px'Img
            & " "
            & Facets_List.Element (i).Vertex_A.py'Img
            & " "
            & Facets_List.Element (i).Vertex_A.pz'Img);
         Put_Line
           (F,
            "      vertex "
            & Facets_List.Element (i).Vertex_B.px'Img
            & " "
            & Facets_List.Element (i).Vertex_B.py'Img
            & " "
            & Facets_List.Element (i).Vertex_B.pz'Img);
         Put_Line
           (F,
            "      vertex "
            & Facets_List.Element (i).Vertex_C.px'Img
            & " "
            & Facets_List.Element (i).Vertex_C.py'Img
            & " "
            & Facets_List.Element (i).Vertex_C.pz'Img);
         Put_Line (F, "    endloop");
         Put_Line (F, "  endfacet");
      end loop;
      Put_Line (F, "endsolid lithophane");
      Close (F);
   end Dump_STL_ASCII;

   procedure Dump_STL_BIN
     (Facets_List : Facets.Vector; Settings : Settings_Record)
   is
      type TQ31 is delta 2.0 ** (-4) range -1.0 .. 1.0 - 2.0 ** (-4);
      F      : Ada.Streams.Stream_IO.File_Type;
      S      : Ada.Streams.Stream_IO.Stream_Access;
      Header : constant String (1 .. 80) := (others => ' ');
      N      : constant Natural := 0;
      P      : constant TQ31 := 0.0;
   begin
      Put_Line ("FACETS" & N'Size'Image & " " & P'Size'Image);
      Create
        (F,
         Out_File,
         Ada.Strings.Unbounded.To_String (Settings.outfilename) & ".bin.stl");
      S := Stream (F);
      String'Write (S, Header);
      Integer'Write (S, Integer'Val (Facets_List.Length));
      for i in Facets_List.First_Index .. Facets_List.Last_Index loop
         Float'Write (S, Facets_List.Element (i).Normal.vx);
         Float'Write (S, Facets_List.Element (i).Normal.vy);
         Float'Write (S, Facets_List.Element (i).Normal.vz);

         Float'Write (S, Facets_List.Element (i).Vertex_A.px);
         Float'Write (S, Facets_List.Element (i).Vertex_A.py);
         Float'Write (S, Facets_List.Element (i).Vertex_A.pz);

         Float'Write (S, Facets_List.Element (i).Vertex_B.px);
         Float'Write (S, Facets_List.Element (i).Vertex_B.py);
         Float'Write (S, Facets_List.Element (i).Vertex_B.pz);

         Float'Write (S, Facets_List.Element (i).Vertex_C.px);
         Float'Write (S, Facets_List.Element (i).Vertex_C.py);
         Float'Write (S, Facets_List.Element (i).Vertex_C.pz);

         Short_Integer'Write (S, 0);
      end loop;
      Close (F);
   end Dump_STL_BIN;

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

   procedure Calculate_Facets
     (the_matrix : Matrix_Access; Settings : Settings_Record)
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
               --  côté gauche
               Visit ((Float (Ix0), Float (J), Z));
            end loop;
            for I in Ix0 .. Ix1 - 1 loop
               --  côté haut
               Visit ((Float (I), Float (Jy1), Z));
            end loop;
            for J in reverse Jy0 + 1 .. Jy1 loop
               --  côté droit
               Visit ((Float (Ix1), Float (J), Z));
            end loop;
            for I in reverse Ix0 + 1 .. Ix1 loop
               --  côté bas
               Visit ((Float (I), Float (Jy0), Z));
            end loop;
            Visit (First_Point);                       --  ferme la boucle
         end;
      end Emit_Flat_Rect_Fan;

   begin
      Done.all := [others => [others => False]];

      --  Le fond est toujours plat sur toute la grille : un seul éventail
      --  suffit pour tout le pourtour, au lieu d'une paire de triangles
      --  par pixel.
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

               --  Surface : fusionne les cellules plates voisines en un
               --  seul rectangle (greedy meshing), sinon triangulation
               --  d'origine, pixel par pixel, géométrie inchangée.
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

               --  Côtés : toujours par cellule unitaire. Le pourtour ne
               --  bénéficie pas de la fusion mais reste bon marché
               --  (proportionnel au périmètre, pas à la surface) et doit
               --  rester à la résolution du pixel pour raccorder
               --  exactement le fond et la surface, fusionnés ou non.
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

      if Settings.save_as_ascii then
         Dump_STL_ASCII (Facets_List, Settings);
      end if;

      if Settings.save_as_binary then
         Dump_STL_BIN (Facets_List, Settings);
      end if;

   end Calculate_Facets;

end Lithophane.STL;
