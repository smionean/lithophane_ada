------------------------------------------------------------------------------
--  lithophane-stl.adb
--
--  Body of Lithophane.STL.
--    * Dump_STL_ASCII writes the human-readable "solid / facet normal /
--      outer loop / vertex" form to "<outfilename>.ascii.stl".
--    * Dump_STL_BIN writes the binary form to "<outfilename>.bin.stl":
--      an 80-byte header, the little-endian triangle count, then one
--      packed record per facet (normal, three vertices, 2-byte attribute).
--
--  Created : 2026-08-23
--  Author  : Simon Beàn
------------------------------------------------------------------------------

with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;

package body Lithophane.STL is

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

end Lithophane.STL;
