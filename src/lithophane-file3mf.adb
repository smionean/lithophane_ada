------------------------------------------------------------------------------
--  lithophane-file3mf.adb
--
--  Body of Lithophane.File3mf. Contains:
--    * vertex welding (coordinates quantised to a 1e-4 grid, hashed map) to
--      turn the triangle "soup" into a closed manifold mesh;
--    * optional scaling of the mesh to a physical size in millimetres;
--    * generation of the 3D/3dmodel.model XML, [Content_Types].xml and
--      _rels/.rels parts;
--    * assembly of the OPC/ZIP archive with the "stored" (uncompressed)
--      method, CRC-32 computed directly, then writing the .3mf file.
--
--  The model part is never materialised as one big string: it is emitted as
--  a stream of small chunks, once to size and checksum it and once to write
--  it into the archive. Only the welded vertex coordinates and the triangle
--  index triples are held in memory, not the (far larger) XML text.
--
--  Created : 2026-09-02
--  Author  : Simon Beàn
--  Helper  : Claude Code
------------------------------------------------------------------------------

with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings;           use Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Characters.Latin_1;
with Ada.Containers;        use Ada.Containers;
with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;
with Interfaces;            use Interfaces;

package body Lithophane.File3mf is

   LF : constant Character := Ada.Characters.Latin_1.LF;

   --  ---------------------------------------------------------------------
   --  Vertex welding.
   --
   --  The facet list carries three independent vertices per triangle, with
   --  no sharing: adjacent triangles hold coincident but distinct copies of
   --  their common corners. An STL slicer welds those by proximity, but a
   --  3MF reader trusts the index topology as given, so every triangle edge
   --  shows up as an "open edge". Collapsing coincident vertices onto a
   --  single shared index turns the soup back into a closed manifold.
   --
   --  Coordinates are quantised to a 1e-4 grid before hashing so that the
   --  tiny rounding differences between the several ways the generator
   --  builds the same corner still map to one key.
   --  ---------------------------------------------------------------------
   Weld_Grid : constant Float := 10_000.0;

   type Vertex_Key is record
      X, Y, Z : Long_Long_Integer;
   end record;

   function To_Key (P : Point) return Vertex_Key
   is (X => Long_Long_Integer (Float'Rounding (P.px * Weld_Grid)),
       Y => Long_Long_Integer (Float'Rounding (P.py * Weld_Grid)),
       Z => Long_Long_Integer (Float'Rounding (P.pz * Weld_Grid)));

   function Key_Hash (K : Vertex_Key) return Hash_Type is
      H : Hash_Type := 2_166_136_261;
   begin
      H := (H xor Hash_Type'Mod (K.X)) * 16_777_619;
      H := (H xor Hash_Type'Mod (K.Y)) * 16_777_619;
      H := (H xor Hash_Type'Mod (K.Z)) * 16_777_619;
      return H;
   end Key_Hash;

   package Vertex_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Vertex_Key,
        Element_Type    => Natural,
        Hash            => Key_Hash,
        Equivalent_Keys => "=");

   --  Welded vertices, in the order their id was assigned, and the triangle
   --  index triples that survive welding. Together these are a fraction of
   --  the size of the model XML they generate, so they can stay resident
   --  while the XML is streamed out twice.
   package Point_Vectors is new
     Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Point);

   type Tri_Indices is record
      A, B, C : Natural;
   end record;

   package Tri_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Tri_Indices);

   --  ---------------------------------------------------------------------
   --  CRC-32 (ISO 3309 / ZIP), computed directly, no lookup table. The
   --  streamed model part feeds its chunks through CRC32_Update.
   --  ---------------------------------------------------------------------
   procedure CRC32_Update (C : in out Unsigned_32; S : String) is
   begin
      for Ch of S loop
         C := C xor Unsigned_32 (Character'Pos (Ch));
         for K in 1 .. 8 loop
            if (C and 1) /= 0 then
               C := Shift_Right (C, 1) xor 16#EDB8_8320#;
            else
               C := Shift_Right (C, 1);
            end if;
         end loop;
      end loop;
   end CRC32_Update;

   function CRC32 (S : String) return Unsigned_32 is
      C : Unsigned_32 := 16#FFFF_FFFF#;
   begin
      CRC32_Update (C, S);
      return C xor 16#FFFF_FFFF#;
   end CRC32;

   --  ---------------------------------------------------------------------
   --  Little-endian primitives for the ZIP records.
   --  ---------------------------------------------------------------------
   procedure Put_U8 (S : Stream_Access; V : Unsigned_8) is
   begin
      Unsigned_8'Write (S, V);
   end Put_U8;

   procedure Put_U16 (S : Stream_Access; V : Unsigned_16) is
   begin
      Put_U8 (S, Unsigned_8 (V and 16#FF#));
      Put_U8 (S, Unsigned_8 (Shift_Right (V, 8) and 16#FF#));
   end Put_U16;

   procedure Put_U32 (S : Stream_Access; V : Unsigned_32) is
   begin
      Put_U8 (S, Unsigned_8 (V and 16#FF#));
      Put_U8 (S, Unsigned_8 (Shift_Right (V, 8) and 16#FF#));
      Put_U8 (S, Unsigned_8 (Shift_Right (V, 16) and 16#FF#));
      Put_U8 (S, Unsigned_8 (Shift_Right (V, 24) and 16#FF#));
   end Put_U32;

   procedure Put_Str (S : Stream_Access; Str : String) is
   begin
      String'Write (S, Str);
   end Put_Str;

   --  ---------------------------------------------------------------------
   --  Dump_3mf
   --  ---------------------------------------------------------------------
   procedure Dump_3mf (Facets_List : Facets.Vector; Settings : Settings_Record)
   is
      --  Fixed DOS timestamp (1980-01-01 00:00:00); a 3MF reader ignores it.
      DOS_Time : constant Unsigned_16 := 0;
      DOS_Date : constant Unsigned_16 := 16#0021#;

      Model_Path : constant String := "3D/3dmodel.model";

      --  Filled in by Weld_Mesh, used only for the progress line.
      Welded_Vertices     : Natural := 0;
      Welded_Triangles    : Natural := 0;
      Out_W, Out_H, Out_D : Float := 0.0;   --  final bounding box, in mm

      function Num (X : Float) return String is
      begin
         return Trim (X'Image, Both);
      end Num;

      --  Welded geometry (output/millimetre space). Built once by Weld_Mesh,
      --  then read (not modified) by Emit_Model on every streaming pass.
      Verts : Point_Vectors.Vector;
      Tris  : Tri_Vectors.Vector;

      D : Dimensions_Type renames Settings.dimensions;

      --  Model-space bounding box (pixel units on X/Y, relief units on Z).
      Min_X, Min_Y, Min_Z : Float := Float'Last;
      Max_X, Max_Y, Max_Z : Float := Float'First;

      Sx, Sy, Sz : Float := 1.0;   --  per-axis scale, model -> mm

      procedure Grow (P : Point) is
      begin
         Min_X := Float'Min (Min_X, P.px);
         Max_X := Float'Max (Max_X, P.px);
         Min_Y := Float'Min (Min_Y, P.py);
         Max_Y := Float'Max (Max_Y, P.py);
         Min_Z := Float'Min (Min_Z, P.pz);
         Max_Z := Float'Max (Max_Z, P.pz);
      end Grow;

      --  A vertex transformed to output (millimetre) space: the box is
      --  moved to the origin, scaled per axis, and X/Y are re-centred so
      --  the model sits symmetrically about (0, 0) like a printer plate.
      function To_MM (P : Point) return Point is
         Ext_X : constant Float := Float'Max (Max_X - Min_X, 1.0e-6);
         Ext_Y : constant Float := Float'Max (Max_Y - Min_Y, 1.0e-6);
      begin
         return
           (px => (P.px - Min_X) * Sx - Ext_X * Sx / 2.0,
            py => (P.py - Min_Y) * Sy - Ext_Y * Sy / 2.0,
            pz => (P.pz - Min_Z) * Sz);
      end To_MM;

      --  Turn the facet soup into welded vertices + triangle index triples.
      --  Runs three linear passes: bounding box, per-axis scale, then weld.
      --  Coincident corners (quantised to Weld_Grid) collapse onto one id;
      --  triangles that degenerate to a line or point once welded are
      --  dropped, so the slicer sees a closed manifold.
      procedure Weld_Mesh is
         Map     : Vertex_Maps.Map;
         Next_Id : Natural := 0;

         function Vertex_Index (P : Point) return Natural is
            K : constant Vertex_Key := To_Key (P);
            C : constant Vertex_Maps.Cursor := Map.Find (K);
         begin
            if Vertex_Maps.Has_Element (C) then
               return Vertex_Maps.Element (C);
            end if;

            declare
               Id : constant Natural := Next_Id;
            begin
               Map.Insert (K, Id);
               Verts.Append (P);
               Next_Id := Next_Id + 1;
               return Id;
            end;
         end Vertex_Index;

      begin
         --  Pass 1: measure the model.
         for I in Facets_List.First_Index .. Facets_List.Last_Index loop
            declare
               F : constant Facet := Facets_List.Element (I);
            begin
               Grow (F.Vertex_A);
               Grow (F.Vertex_B);
               Grow (F.Vertex_C);
            end;
         end loop;

         --  Pass 2: derive the per-axis scale. An axis with a requested
         --  size uses it directly; an unconstrained axis (0.0) borrows the
         --  scale of the first constrained one, so proportions are
         --  preserved. With no dimensions requested every scale stays 1.0.
         declare
            Ext_X : constant Float := Float'Max (Max_X - Min_X, 1.0e-6);
            Ext_Y : constant Float := Float'Max (Max_Y - Min_Y, 1.0e-6);
            Ext_Z : constant Float := Float'Max (Max_Z - Min_Z, 1.0e-6);
            Ref   : constant Float :=
              (if D.width > 0.0
               then D.width / Ext_X
               elsif D.height > 0.0
               then D.height / Ext_Y
               elsif D.depth > 0.0
               then D.depth / Ext_Z
               else 1.0);
         begin
            Sx := (if D.width > 0.0 then D.width / Ext_X else Ref);
            Sy := (if D.height > 0.0 then D.height / Ext_Y else Ref);
            Sz := (if D.depth > 0.0 then D.depth / Ext_Z else Ref);
            Out_W := Ext_X * Sx;
            Out_H := Ext_Y * Sy;
            Out_D := Ext_Z * Sz;
         end;

         --  Pass 3: weld and record the surviving triangles.
         for I in Facets_List.First_Index .. Facets_List.Last_Index loop
            declare
               F  : constant Facet := Facets_List.Element (I);
               A  : constant Natural := Vertex_Index (To_MM (F.Vertex_A));
               B  : constant Natural := Vertex_Index (To_MM (F.Vertex_B));
               Cc : constant Natural := Vertex_Index (To_MM (F.Vertex_C));
            begin
               if A /= B and then B /= Cc and then A /= Cc then
                  Tris.Append (Tri_Indices'(A, B, Cc));
               end if;
            end;
         end loop;

         Welded_Vertices := Next_Id;
         Welded_Triangles := Natural (Tris.Length);
         --  Map is no longer needed; its storage is released on return.
      end Weld_Mesh;

      --  Emit the whole 3D/3dmodel.model XML as a sequence of small chunks
      --  passed to Sink. Called twice: once with a counting/checksumming
      --  sink to fill in the ZIP header, once with a sink that writes to
      --  the archive stream. It only reads Verts and Tris, never mutates.
      procedure Emit_Model (Sink : access procedure (Chunk : String)) is
      begin
         Sink ("<?xml version=""1.0"" encoding=""UTF-8""?>" & LF);
         Sink
           ("<model unit=""millimeter"" xml:lang=""en-US"""
            & " xmlns=""http://schemas.microsoft.com/3dmanufacturing/"
            & "core/2015/02"">"
            & LF);
         Sink (" <resources>" & LF);
         Sink ("  <object id=""1"" type=""model"">" & LF);
         Sink ("   <mesh>" & LF);

         Sink ("    <vertices>" & LF);
         for I in Verts.First_Index .. Verts.Last_Index loop
            declare
               P : constant Point := Verts.Element (I);
            begin
               Sink
                 ("     <vertex x="""
                  & Num (P.px)
                  & """ y="""
                  & Num (P.py)
                  & """ z="""
                  & Num (P.pz)
                  & """/>"
                  & LF);
            end;
         end loop;
         Sink ("    </vertices>" & LF);

         Sink ("    <triangles>" & LF);
         for I in Tris.First_Index .. Tris.Last_Index loop
            declare
               T : constant Tri_Indices := Tris.Element (I);
            begin
               Sink
                 ("     <triangle v1="""
                  & Trim (Natural'Image (T.A), Both)
                  & """ v2="""
                  & Trim (Natural'Image (T.B), Both)
                  & """ v3="""
                  & Trim (Natural'Image (T.C), Both)
                  & """/>"
                  & LF);
            end;
         end loop;
         Sink ("    </triangles>" & LF);

         Sink ("   </mesh>" & LF);
         Sink ("  </object>" & LF);
         Sink (" </resources>" & LF);
         Sink (" <build>" & LF);
         Sink ("  <item objectid=""1""/>" & LF);
         Sink (" </build>" & LF);
         Sink ("</model>" & LF);
      end Emit_Model;

      Content_Types : constant String :=
        "<?xml version=""1.0"" encoding=""UTF-8""?>"
        & LF
        & "<Types xmlns=""http://schemas.openxmlformats.org/package/2006/"
        & "content-types"">"
        & LF
        & " <Default Extension=""rels"" ContentType=""application/"
        & "vnd.openxmlformats-package.relationships+xml""/>"
        & LF
        & " <Default Extension=""model"" ContentType=""application/"
        & "vnd.ms-package.3dmanufacturing-3dmodel+xml""/>"
        & LF
        & "</Types>"
        & LF;

      Rels : constant String :=
        "<?xml version=""1.0"" encoding=""UTF-8""?>"
        & LF
        & "<Relationships xmlns=""http://schemas.openxmlformats.org/"
        & "package/2006/relationships"">"
        & LF
        & " <Relationship Target=""/"
        & Model_Path
        & """ Id=""rel0"""
        & " Type=""http://schemas.microsoft.com/3dmanufacturing/2013/01/"
        & "3dmodel""/>"
        & LF
        & "</Relationships>"
        & LF;

      type Part is record
         Name     : Unbounded_String;
         Body_T   : Unbounded_String;   --  empty for the streamed model part
         Streamed : Boolean := False;   --  body produced by Emit_Model
         CRC      : Unsigned_32 := 0;
         Size     : Unsigned_32 := 0;   --  uncompressed = compressed (stored)
         Offset   : Unsigned_32 := 0;
      end record;

      Parts : array (1 .. 3) of Part;

      F : Ada.Streams.Stream_IO.File_Type;
      S : Stream_Access;

      procedure Write_To_Archive (Str : String) is
      begin
         Put_Str (S, Str);
      end Write_To_Archive;

      procedure Put_Local_Header (P : Part) is
         Name : constant String := To_String (P.Name);
      begin
         Put_U32 (S, 16#0403_4B50#);          --  local file header signature
         Put_U16 (S, 20);                     --  version needed to extract
         Put_U16 (S, 0);                      --  general purpose bit flag
         Put_U16 (S, 0);                      --  compression method: stored
         Put_U16 (S, DOS_Time);
         Put_U16 (S, DOS_Date);
         Put_U32 (S, P.CRC);
         Put_U32 (S, P.Size);                 --  compressed size
         Put_U32 (S, P.Size);                 --  uncompressed size
         Put_U16 (S, Unsigned_16 (Name'Length));
         Put_U16 (S, 0);                       --  extra field length
         Put_Str (S, Name);
         if P.Streamed then
            Emit_Model (Write_To_Archive'Access);
         else
            Put_Str (S, To_String (P.Body_T));
         end if;
      end Put_Local_Header;

      procedure Put_Central_Header (P : Part) is
         Name : constant String := To_String (P.Name);
      begin
         Put_U32 (S, 16#0201_4B50#);          --  central directory signature
         Put_U16 (S, 20);                     --  version made by
         Put_U16 (S, 20);                     --  version needed to extract
         Put_U16 (S, 0);                      --  general purpose bit flag
         Put_U16 (S, 0);                      --  compression method: stored
         Put_U16 (S, DOS_Time);
         Put_U16 (S, DOS_Date);
         Put_U32 (S, P.CRC);
         Put_U32 (S, P.Size);                 --  compressed size
         Put_U32 (S, P.Size);                 --  uncompressed size
         Put_U16 (S, Unsigned_16 (Name'Length));
         Put_U16 (S, 0);                      --  extra field length
         Put_U16 (S, 0);                      --  file comment length
         Put_U16 (S, 0);                      --  disk number start
         Put_U16 (S, 0);                      --  internal file attributes
         Put_U32 (S, 0);                      --  external file attributes
         Put_U32 (S, P.Offset);               --  offset of local header
         Put_Str (S, Name);
      end Put_Central_Header;

      --  Sizing/checksumming sink for the streamed model part. The length
      --  is 64-bit: the XML for a very dense mesh easily passes 2 GB (which
      --  used to overflow a 32-bit Natural before the 4 GB ceiling below
      --  was even reached).
      Model_Len : Unsigned_64 := 0;
      Model_CRC : Unsigned_32 := 16#FFFF_FFFF#;

      procedure Measure_Model (Str : String) is
      begin
         Model_Len := Model_Len + Unsigned_64 (Str'Length);
         CRC32_Update (Model_CRC, Str);
      end Measure_Model;

      --  A plain (non-ZIP64) OPC/ZIP package addresses every part with
      --  32-bit sizes and offsets, so the model part must stay below 4 GB.
      --  A mesh whose XML is larger than that has far more triangles than
      --  a 3D printer can resolve anyway; refuse it with a clear hint
      --  rather than writing a corrupt archive or raising a raw overflow.
      Zip32_Limit : constant Unsigned_64 :=
        Unsigned_64 (Unsigned_32'Last) - 16#1_0000#;   --  room for headers

      CD_Start : Unsigned_32;
      CD_End   : Unsigned_32;

   begin
      Weld_Mesh;

      --  Size and checksum the model part without materialising it.
      Emit_Model (Measure_Model'Access);
      Model_CRC := Model_CRC xor 16#FFFF_FFFF#;

      if Model_Len > Zip32_Limit then
         raise Constraint_Error
           with
             "3MF model would be "
             & Trim (Unsigned_64'Image (Model_Len), Both)
             & " bytes ("
             & Trim (Natural'Image (Welded_Triangles), Both)
             & " triangles), over the 4 GB limit of a plain-ZIP 3MF."
             & " Reduce the image resolution (e.g. `sips -Z 1500 image.jpg`)"
             & " or lower --border.";
      end if;

      Parts (1).Name := To_Unbounded_String ("[Content_Types].xml");
      Parts (1).Body_T := To_Unbounded_String (Content_Types);
      Parts (2).Name := To_Unbounded_String ("_rels/.rels");
      Parts (2).Body_T := To_Unbounded_String (Rels);
      Parts (3).Name := To_Unbounded_String (Model_Path);
      Parts (3).Streamed := True;
      Parts (3).CRC := Model_CRC;
      Parts (3).Size := Unsigned_32 (Model_Len);

      for I in 1 .. 2 loop
         Parts (I).CRC := CRC32 (To_String (Parts (I).Body_T));
         Parts (I).Size := Unsigned_32 (Length (Parts (I).Body_T));
      end loop;

      Create
        (F,
         Out_File,
         Ada.Strings.Unbounded.To_String (Settings.outfilename) & ".3mf");
      S := Stream (F);

      --  Local headers + data.
      for P of Parts loop
         P.Offset := Unsigned_32 (Index (F) - 1);
         Put_Local_Header (P);
      end loop;

      --  Central directory.
      CD_Start := Unsigned_32 (Index (F) - 1);
      for P of Parts loop
         Put_Central_Header (P);
      end loop;
      CD_End := Unsigned_32 (Index (F) - 1);

      --  End of central directory record.
      Put_U32 (S, 16#0605_4B50#);
      Put_U16 (S, 0);                         --  number of this disk
      Put_U16 (S, 0);                         --  disk with central directory
      Put_U16 (S, Unsigned_16 (Parts'Length));  --  entries on this disk
      Put_U16 (S, Unsigned_16 (Parts'Length));  --  total entries
      Put_U32 (S, CD_End - CD_Start);         --  size of central directory
      Put_U32 (S, CD_Start);                  --  offset of central directory
      Put_U16 (S, 0);                         --  .ZIP file comment length

      Close (F);

      Put_Line
        (Standard_Error,
         "Wrote 3MF: "
         & Ada.Strings.Unbounded.To_String (Settings.outfilename)
         & ".3mf ("
         & Trim (Natural'Image (Welded_Vertices), Both)
         & " vertices, "
         & Trim (Natural'Image (Welded_Triangles), Both)
         & " triangles, from "
         & Trim (Natural'Image (Natural (Facets_List.Length)), Both)
         & " facets; "
         & Num (Out_W)
         & " x "
         & Num (Out_H)
         & " x "
         & Num (Out_D)
         & " mm)");
   end Dump_3mf;

end Lithophane.File3mf;
