------------------------------------------------------------------------------
--  lithophane-file3mf.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Body of Lithophane.File3mf. Contains:
--    * vertex welding (coordinates quantised to a 1e-4 grid, hashed map) to
--      turn the triangle "soup" into a closed manifold mesh;
--    * optional scaling of the mesh to a physical size in millimetres;
--    * generation of the 3D/3dmodel.model XML (one mesh object, or several
--      named and coloured ones assembled as components), [Content_Types].xml
--      and _rels/.rels parts, plus, for a coloured model, the settings
--      giving a filament to each part in Bambu Studio;
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
   --  Write_3mf: the writer behind both Dump_3mf. The meshes are referenced,
   --  not copied: a facet list is by far the largest object of the program.
   --  ---------------------------------------------------------------------
   type Facets_Ref is access constant Facets.Vector;

   type Part_Ref is record
      Name     : Unbounded_String;
      Colour   : Colour_Code := "#FFFFFF";
      Filament : Positive := 1;
      Mesh     : Facets_Ref;
   end record;

   type Part_Refs is array (Positive range <>) of Part_Ref;

   --  With Coloured unset there is a single part, written as a bare mesh
   --  object; otherwise every non-empty part gets a name and a material,
   --  and the parts are assembled into one object.
   procedure Write_3mf
     (Sources : Part_Refs; Coloured : Boolean; Settings : Settings_Record)
   is
      --  Fixed DOS timestamp (1980-01-01 00:00:00); a 3MF reader ignores it.
      DOS_Time : constant Unsigned_16 := 0;
      DOS_Date : constant Unsigned_16 := 16#0021#;

      Model_Path : constant String := "3D/3dmodel.model";

      --  Read by Bambu Studio (and the slicers derived from it), whoever
      --  wrote the 3MF file: the filament of every part of an object.
      Slicer_Settings_Path : constant String :=
        "Metadata/model_settings.config";

      --  Filled in by Weld_Mesh, used only for the progress line.
      Welded_Vertices     : Natural := 0;
      Welded_Triangles    : Natural := 0;
      Out_W, Out_H, Out_D : Float := 0.0;   --  final bounding box, in mm

      function Num (X : Float) return String is
      begin
         return Trim (X'Image, Both);
      end Num;

      --  Welded geometry (output/millimetre space) of each part. Built once
      --  by Weld_Mesh, then read (not modified) by Emit_Model on every
      --  streaming pass.
      type Welded_Mesh is record
         Verts : Point_Vectors.Vector;
         Tris  : Tri_Vectors.Vector;
      end record;

      Meshes : array (Sources'Range) of Welded_Mesh;

      Source_Facets : Natural := 0;

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

      --  Turn the facet soups into welded vertices + triangle index triples.
      --  Runs three linear passes: bounding box, per-axis scale, then weld.
      --  Coincident corners (quantised to Weld_Grid) collapse onto one id;
      --  triangles that degenerate to a line or point once welded are
      --  dropped, so the slicer sees a closed manifold. Each part is welded
      --  on its own: two parts never share a vertex.
      procedure Weld_Mesh is
      begin
         --  Pass 1: measure the model.
         for Source of Sources loop
            for I in Source.Mesh.First_Index .. Source.Mesh.Last_Index loop
               declare
                  F : constant Facet := Source.Mesh.Element (I);
               begin
                  Grow (F.Vertex_A);
                  Grow (F.Vertex_B);
                  Grow (F.Vertex_C);
               end;
            end loop;
            Source_Facets := Source_Facets + Natural (Source.Mesh.Length);
         end loop;

         --  Pass 2: derive the per-axis scale. An axis with a requested
         --  size uses it directly; an unconstrained X or Y axis (0.0)
         --  borrows the scale of the first constrained one, so the picture
         --  keeps its aspect ratio. Z is only scaled when a depth is
         --  requested: otherwise it stays at 1.0, so the relief keeps the
         --  height in millimetres set by Settings.height. With no dimensions
         --  requested every scale stays 1.0.
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
            Sz := (if D.depth > 0.0 then D.depth / Ext_Z else 1.0);
            Out_W := Ext_X * Sx;
            Out_H := Ext_Y * Sy;
            Out_D := Ext_Z * Sz;
         end;

         --  Pass 3: weld and record the surviving triangles.
         for N in Sources'Range loop
            declare
               Facets_List : Facets.Vector renames Sources (N).Mesh.all;
               Verts       : Point_Vectors.Vector renames Meshes (N).Verts;
               Tris        : Tri_Vectors.Vector renames Meshes (N).Tris;

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
               for I in Facets_List.First_Index .. Facets_List.Last_Index loop
                  declare
                     F  : constant Facet := Facets_List.Element (I);
                     A  : constant Natural :=
                       Vertex_Index (To_MM (F.Vertex_A));
                     B  : constant Natural :=
                       Vertex_Index (To_MM (F.Vertex_B));
                     Cc : constant Natural :=
                       Vertex_Index (To_MM (F.Vertex_C));
                  begin
                     if A /= B and then B /= Cc and then A /= Cc then
                        Tris.Append (Tri_Indices'(A, B, Cc));
                     end if;
                  end;
               end loop;

               Welded_Vertices := Welded_Vertices + Next_Id;
               Welded_Triangles := Welded_Triangles + Natural (Tris.Length);
               --  Map is no longer needed; its storage is released here.
            end;
         end loop;
      end Weld_Mesh;

      function Id (N : Natural) return String
      is (Trim (Natural'Image (N), Both));

      --  Text as the value of an XML attribute.
      function Escaped (Text : Unbounded_String) return String is
         Result : Unbounded_String;
      begin
         for C of To_String (Text) loop
            case C is
               when '&'    =>
                  Append (Result, "&amp;");

               when '<'    =>
                  Append (Result, "&lt;");

               when '>'    =>
                  Append (Result, "&gt;");

               when '"'    =>
                  Append (Result, "&quot;");

               when others =>
                  Append (Result, C);
            end case;
         end loop;
         return To_String (Result);
      end Escaped;

      --  Resource ids of a coloured model: 1 is the group of colours,
      --  then come the parts and, last, the object assembling them. A
      --  part without any triangle is left out (a mesh may not be empty).
      Materials_Id : constant := 1;

      --  Emit the whole 3D/3dmodel.model XML as a sequence of small chunks
      --  passed to Sink. Called twice: once with a counting/checksumming
      --  sink to fill in the ZIP header, once with a sink that writes to
      --  the archive stream. It only reads Meshes, never mutates.
      procedure Emit_Model (Sink : access procedure (Chunk : String)) is

         procedure Emit_Mesh (Mesh : Welded_Mesh) is
            Verts : Point_Vectors.Vector renames Mesh.Verts;
            Tris  : Tri_Vectors.Vector renames Mesh.Tris;
         begin
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
                     & Id (T.A)
                     & """ v2="""
                     & Id (T.B)
                     & """ v3="""
                     & Id (T.C)
                     & """/>"
                     & LF);
               end;
            end loop;
            Sink ("    </triangles>" & LF);

            Sink ("   </mesh>" & LF);
         end Emit_Mesh;

         Next_Object  : Natural := Materials_Id + 1;
         Material     : Natural := 0;

      begin
         Sink ("<?xml version=""1.0"" encoding=""UTF-8""?>" & LF);
         Sink
           ("<model unit=""millimeter"" xml:lang=""en-US"""
            & " xmlns=""http://schemas.microsoft.com/3dmanufacturing/"
            & "core/2015/02"""
            & (if Coloured
               then
                 " xmlns:m=""http://schemas.microsoft.com/"
                 & "3dmanufacturing/material/2015/02"""
               else "")
            & ">"
            & LF);
         Sink (" <resources>" & LF);

         if not Coloured then
            Sink ("  <object id=""1"" type=""model"">" & LF);
            Emit_Mesh (Meshes (Meshes'First));
            Sink ("  </object>" & LF);
            Sink (" </resources>" & LF);
            Sink (" <build>" & LF);
            Sink ("  <item objectid=""1""/>" & LF);

         else
            --  A colour group of the materials extension rather than core
            --  base materials: it is the one Bambu Studio reads the colours
            --  of a 3MF file from. The prefix has to be "m" for it.
            Sink ("  <m:colorgroup id=""" & Id (Materials_Id) & """>" & LF);
            for N in Sources'Range loop
               if not Meshes (N).Tris.Is_Empty then
                  Sink
                    ("   <m:color color="""
                     & Sources (N).Colour
                     & "FF""/>"
                     & LF);
               end if;
            end loop;
            Sink ("  </m:colorgroup>" & LF);

            for N in Sources'Range loop
               if not Meshes (N).Tris.Is_Empty then
                  Sink
                    ("  <object id="""
                     & Id (Next_Object)
                     & """ name="""
                     & Escaped (Sources (N).Name)
                     & """ type=""model"" pid="""
                     & Id (Materials_Id)
                     & """ pindex="""
                     & Id (Material)
                     & """>"
                     & LF);
                  Emit_Mesh (Meshes (N));
                  Sink ("  </object>" & LF);
                  Next_Object := Next_Object + 1;
                  Material := Material + 1;
               end if;
            end loop;

            Sink
              ("  <object id="""
               & Id (Next_Object)
               & """ type=""model"">"
               & LF);
            Sink ("   <components>" & LF);
            for Part_Id in Materials_Id + 1 .. Next_Object - 1 loop
               Sink
                 ("    <component objectid=""" & Id (Part_Id) & """/>" & LF);
            end loop;
            Sink ("   </components>" & LF);
            Sink ("  </object>" & LF);
            Sink (" </resources>" & LF);
            Sink (" <build>" & LF);
            Sink ("  <item objectid=""" & Id (Next_Object) & """/>" & LF);
         end if;

         Sink (" </build>" & LF);
         Sink ("</model>" & LF);
      end Emit_Model;

      --  The settings of a coloured model for the slicer: each part is
      --  printed with its filament, and the object itself with the one of
      --  its last part. The ids are those given by Emit_Model.
      function Slicer_Settings return String is
         Result      : Unbounded_String;
         Next_Object : Natural := Materials_Id + 1;
         Last        : Positive := 1;
      begin
         for N in Sources'Range loop
            if not Meshes (N).Tris.Is_Empty then
               Append
                 (Result,
                  "  <part id="""
                  & Id (Next_Object)
                  & """ subtype=""normal_part"">"
                  & LF
                  & "   <metadata key=""name"" value="""
                  & Escaped (Sources (N).Name)
                  & """/>"
                  & LF
                  & "   <metadata key=""extruder"" value="""
                  & Id (Sources (N).Filament)
                  & """/>"
                  & LF
                  & "  </part>"
                  & LF);
               Next_Object := Next_Object + 1;
               Last := Sources (N).Filament;
            end if;
         end loop;

         return
           "<?xml version=""1.0"" encoding=""UTF-8""?>"
           & LF
           & "<config>"
           & LF
           & " <object id="""
           & Id (Next_Object)
           & """>"
           & LF
           & "  <metadata key=""name"" value=""lithophane""/>"
           & LF
           & "  <metadata key=""extruder"" value="""
           & Id (Last)
           & """/>"
           & LF
           & To_String (Result)
           & " </object>"
           & LF
           & "</config>"
           & LF;
      end Slicer_Settings;

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
        & (if Coloured
           then
             " <Default Extension=""config"" ContentType="
             & """application/xml""/>"
             & LF
           else "")
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

      Parts : array (1 .. (if Coloured then 4 else 3)) of Part;

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

      if Coloured then
         Parts (4).Name := To_Unbounded_String (Slicer_Settings_Path);
         Parts (4).Body_T := To_Unbounded_String (Slicer_Settings);
      end if;

      for P of Parts loop
         if not P.Streamed then
            P.CRC := CRC32 (To_String (P.Body_T));
            P.Size := Unsigned_32 (Length (P.Body_T));
         end if;
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
         & Id (Source_Facets)
         & " facets; "
         & Num (Out_W)
         & " x "
         & Num (Out_H)
         & " x "
         & Num (Out_D)
         & " mm)");

      --  Which parts made it into the file: a picture without a given ink
      --  (or without any colour at all) has no part for it.
      if Coloured then
         Put (Standard_Error, "Parts:");
         for N in Sources'Range loop
            if not Meshes (N).Tris.Is_Empty then
               Put
                 (Standard_Error,
                  " "
                  & To_String (Sources (N).Name)
                  & " (filament"
                  & Sources (N).Filament'Image
                  & ")");
            end if;
         end loop;
         New_Line (Standard_Error);
      end if;
   end Write_3mf;

   --  ---------------------------------------------------------------------
   --  Dump_3mf
   --  ---------------------------------------------------------------------
   procedure Dump_3mf (Facets_List : Facets.Vector; Settings : Settings_Record)
   is
   begin
      Write_3mf
        ([1 => (Mesh => Facets_List'Unchecked_Access, others => <>)],
         Coloured => False,
         Settings => Settings);
   end Dump_3mf;

   procedure Dump_3mf (Parts : Model_Parts; Settings : Settings_Record) is
      Sources : Part_Refs (Parts'Range);
   begin
      for N in Parts'Range loop
         Sources (N) :=
           (Name     => Parts (N).Name,
            Colour   => Parts (N).Colour,
            Filament => Parts (N).Filament,
            Mesh     => Parts (N).Mesh'Unchecked_Access);
      end loop;
      Write_3mf (Sources, Coloured => True, Settings => Settings);
   end Dump_3mf;

end Lithophane.File3mf;
