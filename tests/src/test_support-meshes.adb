------------------------------------------------------------------------------
--  test_support-meshes.adb
------------------------------------------------------------------------------

with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;

with AUnit.Assertions; use AUnit.Assertions;

with GNAT.CRC32;

package body Test_Support.Meshes is

   use Ada.Strings.Unbounded;
   use Interfaces;

   Model_Part : constant String := "3D/3dmodel.model";

   --  How many triangles use each edge, an edge being named after its two
   --  ends.
   package Edge_Maps is new
     Ada.Containers.Indefinite_Hashed_Maps
       (Key_Type        => String,
        Element_Type    => Natural,
        Hash            => Ada.Strings.Hash,
        Equivalent_Keys => "=");

   procedure Add_Edge (Edges : in out Edge_Maps.Map; A, B : String) is
      Key      : constant String :=
        (if A < B then A & "|" & B else B & "|" & A);
      Position : constant Edge_Maps.Cursor := Edges.Find (Key);
   begin
      if Edge_Maps.Has_Element (Position) then
         Edges.Replace_Element (Position, Edge_Maps.Element (Position) + 1);
      else
         Edges.Insert (Key, 1);
      end if;
   end Add_Edge;

   --  Record the edge that goes from A to B; Repeated counts the edges
   --  already seen in that direction.
   procedure Add_Directed_Edge
     (Edges : in out Edge_Maps.Map; A, B : String; Repeated : in out Natural)
   is
      Key : constant String := A & ">" & B;
   begin
      if Edges.Contains (Key) then
         Repeated := Repeated + 1;
      else
         Edges.Insert (Key, 1);
      end if;
   end Add_Directed_Edge;

   function Not_Shared_By_Two (Edges : Edge_Maps.Map) return Natural is
      Result : Natural := 0;
   begin
      for Uses of Edges loop
         if Uses /= 2 then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Not_Shared_By_Two;

   --  A name for the position of P, on a 1/1000 grid.
   function Key (P : Point) return String
   is (Integer'Image (Integer (P.px * 1_000.0))
       & Integer'Image (Integer (P.py * 1_000.0))
       & Integer'Image (Integer (P.pz * 1_000.0)));

   procedure Grow (B : in out Box; P : Point) is
   begin
      B.Min :=
        (Float'Min (B.Min.px, P.px),
         Float'Min (B.Min.py, P.py),
         Float'Min (B.Min.pz, P.pz));
      B.Max :=
        (Float'Max (B.Max.px, P.px),
         Float'Max (B.Max.py, P.py),
         Float'Max (B.Max.pz, P.pz));
   end Grow;

   function Bounding_Box (Mesh : Facets.Vector) return Box is
      Result : Box;
   begin
      for F of Mesh loop
         Grow (Result, F.Vertex_A);
         Grow (Result, F.Vertex_B);
         Grow (Result, F.Vertex_C);
      end loop;
      return Result;
   end Bounding_Box;

   function Open_Edges (Mesh : Facets.Vector) return Natural is
      Edges : Edge_Maps.Map;
   begin
      for F of Mesh loop
         Add_Edge (Edges, Key (F.Vertex_A), Key (F.Vertex_B));
         Add_Edge (Edges, Key (F.Vertex_B), Key (F.Vertex_C));
         Add_Edge (Edges, Key (F.Vertex_C), Key (F.Vertex_A));
      end loop;
      return Not_Shared_By_Two (Edges);
   end Open_Edges;

   function Misoriented_Edges (Mesh : Facets.Vector) return Natural is
      Edges  : Edge_Maps.Map;
      Result : Natural := 0;
   begin
      for F of Mesh loop
         Add_Directed_Edge (Edges, Key (F.Vertex_A), Key (F.Vertex_B), Result);
         Add_Directed_Edge (Edges, Key (F.Vertex_B), Key (F.Vertex_C), Result);
         Add_Directed_Edge (Edges, Key (F.Vertex_C), Key (F.Vertex_A), Result);
      end loop;
      return Result;
   end Misoriented_Edges;

   function Degenerate_Facets (Mesh : Facets.Vector) return Natural is
      Result : Natural := 0;
   begin
      for F of Mesh loop
         --  Calculate_Normal returns the null vector for a null area.
         if Calculate_Normal (F.Vertex_A, F.Vertex_B, F.Vertex_C)
           = Vector'(others => 0.0)
         then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Degenerate_Facets;

   function Has_Vertex (Mesh : Facets.Vector; X, Y, Z : Float) return Boolean
   is
      Wanted : constant String := Key ((X, Y, Z));
   begin
      return
        (for some F of Mesh =>
           Key (F.Vertex_A) = Wanted
           or else Key (F.Vertex_B) = Wanted
           or else Key (F.Vertex_C) = Wanted);
   end Has_Vertex;

   function Read_Binary_STL (Path : String) return Facets.Vector is
      F         : File_Type;
      S         : Stream_Access;
      Header    : String (1 .. 80);
      Count     : Integer;
      Attribute : Short_Integer;
      Result    : Facets.Vector;

      function Next_Triple return Point is
         P : Point;
      begin
         Float'Read (S, P.px);
         Float'Read (S, P.py);
         Float'Read (S, P.pz);
         return P;
      end Next_Triple;
   begin
      Open (F, In_File, Path);
      S := Stream (F);
      String'Read (S, Header);
      Integer'Read (S, Count);
      for I in 1 .. Count loop
         declare
            N : constant Point := Next_Triple;
            A : constant Point := Next_Triple;
            B : constant Point := Next_Triple;
            C : constant Point := Next_Triple;
         begin
            Short_Integer'Read (S, Attribute);
            Result.Append
              (Facet'
                 (Normal   => (N.px, N.py, N.pz),
                  Vertex_A => A,
                  Vertex_B => B,
                  Vertex_C => C));
         end;
      end loop;
      Close (F);
      return Result;
   end Read_Binary_STL;

   function CRC_32 (Data : String) return Unsigned_32 is
      C : GNAT.CRC32.CRC32;
   begin
      GNAT.CRC32.Initialize (C);
      GNAT.CRC32.Update (C, Data);
      return GNAT.CRC32.Get_Value (C);
   end CRC_32;

   function Read_Zip (Path : String) return Zip_Part_Vectors.Vector is
      Archive : constant String := Read_File (Path);
      Result  : Zip_Part_Vectors.Vector;

      --  Little-endian values at the 0-based Offset of the archive.
      function U16 (Offset : Natural) return Natural
      is (Character'Pos (Archive (Offset + 1))
          + 256 * Character'Pos (Archive (Offset + 2)));

      function U32 (Offset : Natural) return Unsigned_32
      is (Unsigned_32 (U16 (Offset))
          + 65_536 * Unsigned_32 (U16 (Offset + 2)));

      End_Record_Size : constant := 22;
      End_Record      : Integer;
      Central         : Natural;
   begin
      Assert (Archive'Length >= End_Record_Size, Path & " is not a ZIP file");
      End_Record := Archive'Length - End_Record_Size;
      Assert
        (U32 (End_Record) = 16#0605_4B50#,
         Path & ": no end of central directory record");
      Central := Natural (U32 (End_Record + 16));
      Assert
        (Central + Natural (U32 (End_Record + 12)) = End_Record,
         Path & ": the central directory does not end the archive");

      for I in 1 .. U16 (End_Record + 10) loop
         Assert
           (U32 (Central) = 16#0201_4B50#,
            Path & ": bad central directory entry");
         declare
            Name_Length : constant Natural := U16 (Central + 28);
            Name        : constant String :=
              Archive (Central + 47 .. Central + 46 + Name_Length);
            Size        : constant Natural := Natural (U32 (Central + 24));
            Local       : constant Natural := Natural (U32 (Central + 42));
            Data        : constant Natural :=
              Local + 30 + U16 (Local + 26) + U16 (Local + 28);
         begin
            Assert
              (U32 (Local) = 16#0403_4B50#,
               Path & ": bad local header for " & Name);
            Assert
              (U16 (Central + 10) = 0 and then U16 (Local + 8) = 0,
               Path & ": " & Name & " is not stored");
            Assert
              (Archive (Local + 31 .. Local + 30 + U16 (Local + 26)) = Name,
               Path & ": local header name differs for " & Name);
            Assert
              (U32 (Local + 14) = U32 (Central + 16)
               and then U32 (Local + 18) = U32 (Central + 20)
               and then U32 (Local + 22) = U32 (Central + 24),
               Path & ": local and central headers differ for " & Name);
            Result.Append
              (Zip_Part'
                 (Name => To_Unbounded_String (Name),
                  Data =>
                    To_Unbounded_String (Archive (Data + 1 .. Data + Size)),
                  CRC  => U32 (Central + 16)));
            Central := Central + 46 + Name_Length;
         end;
      end loop;
      return Result;
   end Read_Zip;

   --  The value of the attribute Name in the XML element Element.
   function Attribute (Element : String; Name : String) return String is
      Start  : constant String := " " & Name & "=""";
      First  : constant Natural := Ada.Strings.Fixed.Index (Element, Start);
      Last   : Natural;
   begin
      Assert (First /= 0, "no attribute " & Name & " in " & Element);
      Last :=
        Ada.Strings.Fixed.Index (Element, """", First + Start'Length);
      return Element (First + Start'Length .. Last - 1);
   end Attribute;

   function Read_3MF (Path : String) return Model is
      Result : Model;
      Found  : Boolean := False;

      procedure Parse (XML : String) is
         First : Positive := XML'First;
         Last  : Natural;
      begin
         --  One element per line.
         while First <= XML'Last loop
            Last := Ada.Strings.Fixed.Index (XML, [1 => ASCII.LF], First);
            exit when Last = 0;
            declare
               Line : constant String := XML (First .. Last - 1);
            begin
               if Contains (Line, "<vertex ") then
                  Result.Vertices.Append
                    (Point'
                       (px => Float'Value (Attribute (Line, "x")),
                        py => Float'Value (Attribute (Line, "y")),
                        pz => Float'Value (Attribute (Line, "z"))));
               elsif Contains (Line, "<triangle ") then
                  Result.Triangles.Append
                    (Triangle'
                       (V1 => Natural'Value (Attribute (Line, "v1")),
                        V2 => Natural'Value (Attribute (Line, "v2")),
                        V3 => Natural'Value (Attribute (Line, "v3"))));
               end if;
            end;
            First := Last + 1;
         end loop;
      end Parse;
   begin
      for Part of Read_Zip (Path) loop
         if To_String (Part.Name) = Model_Part then
            Parse (To_String (Part.Data));
            Found := True;
         end if;
      end loop;
      Assert (Found, Path & ": no " & Model_Part & " part");
      return Result;
   end Read_3MF;

   function Bounding_Box (Mesh : Model) return Box is
      Result : Box;
   begin
      for P of Mesh.Vertices loop
         Grow (Result, P);
      end loop;
      return Result;
   end Bounding_Box;

   function Open_Edges (Mesh : Model) return Natural is
      Edges : Edge_Maps.Map;
   begin
      for T of Mesh.Triangles loop
         Add_Edge (Edges, T.V1'Image, T.V2'Image);
         Add_Edge (Edges, T.V2'Image, T.V3'Image);
         Add_Edge (Edges, T.V3'Image, T.V1'Image);
      end loop;
      return Not_Shared_By_Two (Edges);
   end Open_Edges;

   function Misoriented_Edges (Mesh : Model) return Natural is
      Edges  : Edge_Maps.Map;
      Result : Natural := 0;
   begin
      for T of Mesh.Triangles loop
         Add_Directed_Edge (Edges, T.V1'Image, T.V2'Image, Result);
         Add_Directed_Edge (Edges, T.V2'Image, T.V3'Image, Result);
         Add_Directed_Edge (Edges, T.V3'Image, T.V1'Image, Result);
      end loop;
      return Result;
   end Misoriented_Edges;

end Test_Support.Meshes;
