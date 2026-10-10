------------------------------------------------------------------------------
--  colour_tests.adb
--
--  Copyright (c) 2026 Simon Beàn
--  SPDX-License-Identifier: MIT
--
--  Regression tests for Lithophane.Colour: a pixel is split into its inks
--  and its black, and the colour lithophane is a stack of closed parts (a
--  white sheet, an ink layer only where the picture holds that ink, the
--  white lithophane on top) written as one 3MF object.
------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions; use AUnit.Assertions;

with Lithophane;          use Lithophane;
with Lithophane.Colour;   use Lithophane.Colour;
with Lithophane.File3mf;
with Test_Support;        use Test_Support;
with Test_Support.Meshes; use Test_Support.Meshes;

package body Colour_Tests is

   subtype Test_Case is AUnit.Test_Cases.Test_Case'Class;

   Relief_Height : constant Float := 6.0;

   Width  : constant := 6;
   Height : constant := 5;

   function With_Depth (Depth : Float := 0.0) return Settings_Record
   is (height     => Relief_Height,
       dimensions => (depth => Depth, others => 0.0),
       others     => <>);

   --  A flat height map, half as high as the relief may be, with one peak.
   function Relief return Matrix_Grey_Access is
      Image : constant Matrix_Grey_Access := Flat_Matrix (Width, Height, 0.5);
   begin
      Image (2, 2) := 1.0;
      return Image;
   end Relief;

   function No_Ink return Ink_Maps
   is [others => Flat_Matrix (Width, Height, 0.0)];

   procedure Assert_Closed (Part : File3mf.Model_Part) is
      Name : constant String := To_String (Part.Name);
   begin
      Assert (not Part.Mesh.Is_Empty, "the " & Name & " part is empty");
      Assert
        (Open_Edges (Part.Mesh) = 0,
         "the "
         & Name
         & " part has"
         & Open_Edges (Part.Mesh)'Image
         & " open edges");
      Assert
        (Misoriented_Edges (Part.Mesh) = 0,
         "the triangles of the "
         & Name
         & " part do not all turn the same way");
      Assert
        (Degenerate_Facets (Part.Mesh) = 0,
         "the " & Name & " part has triangles without area");
   end Assert_Closed;

   procedure Assert_Z
     (Part : File3mf.Model_Part; Bottom, Top : Float; What : String)
   is
      Size : constant Box := Bounding_Box (Part.Mesh);
      Name : constant String := What & ", " & To_String (Part.Name);
   begin
      Assert_Near (Size.Min.pz, Bottom, Name & ": bottom");
      Assert_Near (Size.Max.pz, Top, Name & ": top");
   end Assert_Z;

   procedure Split_Of_A_Pixel (T : in out Test_Case) is
      pragma Unreferenced (T);

      procedure Check (Red, Green, Blue : Color_Type; C, M, Y, K : Float) is
         What  : constant String := Red'Image & Green'Image & Blue'Image;
         Inks  : Ink_Values;
         Black : Grey_Type;
      begin
         To_CMYK (Red, Green, Blue, Inks, Black);
         Assert_Near (Float (Inks (Cyan)), C, What & ": cyan");
         Assert_Near (Float (Inks (Magenta)), M, What & ": magenta");
         Assert_Near (Float (Inks (Yellow)), Y, What & ": yellow");
         Assert_Near (Float (Black), K, What & ": black");
      end Check;
   begin
      Check (255, 255, 255, 0.0, 0.0, 0.0, 0.0);
      Check (0, 0, 0, 0.0, 0.0, 0.0, 1.0);
      Check (102, 102, 102, 0.0, 0.0, 0.0, 0.6);
      Check (255, 0, 0, 0.0, 1.0, 1.0, 0.0);
      Check (0, 255, 0, 1.0, 0.0, 1.0, 0.0);
      Check (0, 0, 255, 1.0, 1.0, 0.0, 0.0);
      Check (0, 255, 255, 1.0, 0.0, 0.0, 0.0);
      Check (204, 102, 51, 0.0, 0.5, 0.75, 0.2);
   end Split_Of_A_Pixel;

   --  Without any ink only the white sheet and the white lithophane lying
   --  on it are left.
   procedure Picture_Without_Colour (T : in out Test_Case) is
      pragma Unreferenced (T);
      Parts : Layer_Parts;
   begin
      Calculate_Layers (Relief, No_Ink, With_Depth, Parts);
      for N in Cyan_Part .. Yellow_Part loop
         Assert
           (Parts (N).Mesh.Is_Empty,
            "the " & To_String (Parts (N).Name) & " part is not empty");
      end loop;
      Assert_Closed (Parts (Back_Part));
      Assert_Closed (Parts (White_Part));
      Assert_Z (Parts (Back_Part), 0.0, Back_Thickness, "no ink");
      Assert_Z
        (Parts (White_Part),
         Back_Thickness,
         Back_Thickness + Base_Thickness + Relief_Height,
         "no ink");
      Assert
        (Parts (Back_Part).Filament = White_Filament
         and then Parts (Cyan_Part).Filament = Cyan_Filament
         and then Parts (Magenta_Part).Filament = Magenta_Filament
         and then Parts (Yellow_Part).Filament = Yellow_Filament
         and then Parts (White_Part).Filament = White_Filament,
         "unexpected filaments of the parts");
      Assert
        (To_String (Parts (Back_Part).Name) = "white back"
         and then To_String (Parts (Cyan_Part).Name) = "cyan"
         and then To_String (Parts (Magenta_Part).Name) = "magenta"
         and then To_String (Parts (Yellow_Part).Name) = "yellow"
         and then To_String (Parts (White_Part).Name) = "white",
         "unexpected names of the parts");
   end Picture_Without_Colour;

   --  Every ink layer is as thick as its ink, and the parts lie on one
   --  another: the white sheet, cyan, magenta, yellow, then the white
   --  lithophane.
   procedure Layers_Are_Stacked (T : in out Test_Case) is
      pragma Unreferenced (T);
      Inks  : constant Ink_Maps :=
        [Cyan    => Flat_Matrix (Width, Height, 1.0),
         Magenta => Flat_Matrix (Width, Height, 0.5),
         Yellow  => Flat_Matrix (Width, Height, 0.25)];
      Parts : Layer_Parts;
      T0    : constant Float := Back_Thickness;
      T1    : constant Float := T0 + Ink_Thickness;
      T2    : constant Float := T1 + 0.5 * Ink_Thickness;
      T3    : constant Float := T2 + 0.25 * Ink_Thickness;
   begin
      Calculate_Layers (Relief, Inks, With_Depth, Parts);
      for Part of Parts loop
         Assert_Closed (Part);
      end loop;
      Assert_Z (Parts (Back_Part), 0.0, T0, "stack");
      Assert_Z (Parts (Cyan_Part), T0, T1, "stack");
      Assert_Z (Parts (Magenta_Part), T1, T2, "stack");
      Assert_Z (Parts (Yellow_Part), T2, T3, "stack");
      Assert_Z
        (Parts (White_Part),
         T3,
         T3 + Base_Thickness + Relief_Height,
         "stack");
      --  The white part is as thick as without ink.
      Assert
        (Has_Vertex
           (Parts (White_Part).Mesh,
            1.0,
            1.0,
            T3 + Base_Thickness + Relief_Height / 2.0),
         "the relief is not carried over the ink layers");
   end Layers_Are_Stacked;

   --  An ink layer exists only where the picture holds that ink, and the
   --  white part fills the room it leaves.
   procedure Ink_In_One_Place (T : in out Test_Case) is
      pragma Unreferenced (T);
      Inks  : constant Ink_Maps := No_Ink;
      Parts : Layer_Parts;
      Spot  : Box;
   begin
      Inks (Magenta) (4, 3) := 1.0;
      --  Too little ink to be printed.
      Inks (Yellow) (2, 4) := Min_Ink / 2.0;
      Calculate_Layers (Relief, Inks, With_Depth, Parts);

      Assert (Parts (Cyan_Part).Mesh.Is_Empty, "there is a cyan part");
      Assert (Parts (Yellow_Part).Mesh.Is_Empty, "there is a yellow part");
      Assert_Closed (Parts (Magenta_Part));
      Assert_Closed (Parts (White_Part));

      Spot := Bounding_Box (Parts (Magenta_Part).Mesh);
      Assert_Near (Spot.Min.px, 3.0, "spot: min X");
      Assert_Near (Spot.Max.px, 5.0, "spot: max X");
      Assert_Near (Spot.Min.py, 2.0, "spot: min Y");
      Assert_Near (Spot.Max.py, 4.0, "spot: max Y");
      Assert_Z
        (Parts (Magenta_Part),
         Back_Thickness,
         Back_Thickness + Ink_Thickness,
         "spot");

      Assert
        (Has_Vertex
           (Parts (White_Part).Mesh,
            4.0,
            3.0,
            Back_Thickness + Ink_Thickness),
         "the white part does not lie on the ink");
      Assert
        (Has_Vertex
           (Parts (White_Part).Mesh,
            4.0,
            3.0,
            Back_Thickness
            + Ink_Thickness
            + Base_Thickness
            + Relief_Height / 2.0),
         "the relief is not raised by the ink under it");
      Assert_Z
        (Parts (White_Part),
         Back_Thickness,
         Back_Thickness + Base_Thickness + Relief_Height,
         "spot");
   end Ink_In_One_Place;

   --  Ink on both sides of an edge that holds none: the layer is opened
   --  there instead of being pinched, so it stays a manifold.
   procedure No_Pinched_Edge (T : in out Test_Case) is
      pragma Unreferenced (T);
      Parts : Layer_Parts;

      procedure Check (I1, J1, I2, J2 : Positive; What : String) is
         Inks : constant Ink_Maps := No_Ink;
      begin
         Inks (Cyan) (I1, J1) := 1.0;
         Inks (Cyan) (I2, J2) := 1.0;
         Calculate_Layers (Relief, Inks, With_Depth, Parts);
         Assert
           (Open_Edges (Parts (Cyan_Part).Mesh) = 0,
            What
            & ":"
            & Open_Edges (Parts (Cyan_Part).Mesh)'Image
            & " edges of the cyan part do not bound two triangles");
         Assert_Closed (Parts (Cyan_Part));
         Assert_Closed (Parts (White_Part));
         Assert_Z
           (Parts (Cyan_Part),
            Back_Thickness,
            Back_Thickness + Ink_Thickness,
            What);
      end Check;

      Rows : constant Ink_Maps :=
        [Cyan   => Flat_Matrix (Width, Height, 0.0),
         others => Flat_Matrix (Width, Height, 0.0)];
   begin
      Check (3, 4, 4, 2, "edge along X");
      Check (4, 3, 2, 4, "edge along Y");
      Check (3, 3, 4, 4, "diagonal");

      --  Every other row inked: each row in between is a gap to open.
      for I in 1 .. Width loop
         Rows (Cyan) (I, 2) := 1.0;
         Rows (Cyan) (I, 4) := 1.0;
      end loop;
      Calculate_Layers (Relief, Rows, With_Depth, Parts);
      Assert_Closed (Parts (Cyan_Part));
      Assert_Closed (Parts (White_Part));
   end No_Pinched_Edge;

   --  A depth is the thickness of the white part; the white sheet and the
   --  ink layers keep theirs and come on top of it.
   procedure Depth_Is_For_The_White_Part (T : in out Test_Case) is
      pragma Unreferenced (T);
      Inks  : constant Ink_Maps :=
        [Cyan   => Flat_Matrix (Width, Height, 1.0),
         others => Flat_Matrix (Width, Height, 0.0)];
      Parts : Layer_Parts;
   begin
      Calculate_Layers (Relief, Inks, With_Depth (2.0), Parts);
      Assert_Z (Parts (Back_Part), 0.0, Back_Thickness, "depth");
      Assert_Z
        (Parts (Cyan_Part),
         Back_Thickness,
         Back_Thickness + Ink_Thickness,
         "depth");
      Assert_Z
        (Parts (White_Part),
         Back_Thickness + Ink_Thickness,
         Back_Thickness + Ink_Thickness + 2.0,
         "depth");
   end Depth_Is_For_The_White_Part;

   procedure Inks_Of_Another_Size (T : in out Test_Case) is
      pragma Unreferenced (T);
      Inks  : constant Ink_Maps :=
        [others => Flat_Matrix (Width + 1, Height, 0.0)];
      Parts : Layer_Parts;
   begin
      Calculate_Layers (Relief, Inks, With_Depth, Parts);
      Assert (False, "inks larger than the height map were accepted");
   exception
      when Constraint_Error =>
         null;
   end Inks_Of_Another_Size;

   --  One object made of a named, coloured part per ink of the picture.
   procedure File_Of_Parts (T : in out Test_Case) is
      pragma Unreferenced (T);
      Inks     : constant Ink_Maps := No_Ink;
      Settings : Settings_Record := With_Depth (4.0);
      Size     : Box;
   begin
      Reset_Scratch;
      Inks (Cyan) (3, 3) := 1.0;
      Inks (Yellow) (3, 3) := 0.5;
      Settings.outfilename := To_Unbounded_String (Scratch ("parts"));
      Settings.dimensions.width := 50.0;
      Dump_Colour_3mf (Relief, Inks, Settings);

      declare
         XML : constant String :=
           To_String (Read_Zip (Scratch ("parts.3mf")) (3).Data);
      begin
         Assert
           (Contains
              (XML,
               "  <m:colorgroup id=""1"">"
               & ASCII.LF
               & "   <m:color color=""#FFFFFFFF""/>"
               & ASCII.LF
               & "   <m:color color=""#00FFFFFF""/>"
               & ASCII.LF
               & "   <m:color color=""#FFFF00FF""/>"
               & ASCII.LF
               & "   <m:color color=""#FFFFFFFF""/>"
               & ASCII.LF
               & "  </m:colorgroup>")
            and then
              Contains
                (XML,
                 "xmlns:m=""http://schemas.microsoft.com/3dmanufacturing/"
                 & "material/2015/02"""),
            "the colours of the parts are missing");
         Assert
           (Contains
              (XML,
               "<object id=""2"" name=""white back"" type=""model"""
               & " pid=""1"" pindex=""0"">")
            and then
              Contains
                (XML,
                 "<object id=""3"" name=""cyan"" type=""model"" pid=""1"""
                 & " pindex=""1"">")
            and then
              Contains
                (XML,
                 "<object id=""4"" name=""yellow"" type=""model"" pid=""1"""
                 & " pindex=""2"">")
            and then
              Contains
                (XML,
                 "<object id=""5"" name=""white"" type=""model"" pid=""1"""
                 & " pindex=""3"">"),
            "the parts are missing");
         Assert
           (not Contains (XML, "magenta"),
            "a part without ink has been written");
         Assert
           (Occurrences (XML, "<mesh>") = 4
            and then Occurrences (XML, "<component ") = 4
            and then Contains (XML, "<component objectid=""2""/>")
            and then Contains (XML, "<component objectid=""3""/>")
            and then Contains (XML, "<component objectid=""4""/>")
            and then Contains (XML, "<component objectid=""5""/>")
            and then Contains (XML, "<object id=""6"" type=""model"">")
            and then Contains (XML, "<item objectid=""6""/>"),
            "the parts are not assembled into the object of the build");
      end;

      --  The filament of each part, for Bambu Studio: it does not change
      --  when another part (here magenta) is left out, and both white
      --  parts share one.
      declare
         Files    : constant Zip_Part_Vectors.Vector :=
           Read_Zip (Scratch ("parts.3mf"));
         Settings : constant String := To_String (Files (4).Data);

         function Part
           (Id : String; Name : String; Filament : String) return String
         is ("  <part id="""
             & Id
             & """ subtype=""normal_part"">"
             & ASCII.LF
             & "   <metadata key=""name"" value="""
             & Name
             & """/>"
             & ASCII.LF
             & "   <metadata key=""extruder"" value="""
             & Filament
             & """/>"
             & ASCII.LF
             & "  </part>"
             & ASCII.LF);
      begin
         Assert
           (Natural (Files.Length) = 4
            and then
              To_String (Files (4).Name) = "Metadata/model_settings.config",
            "the settings for the slicer are missing");
         Assert
           (Contains
              (Settings,
               " <object id=""6"">"
               & ASCII.LF
               & "  <metadata key=""name"" value=""lithophane""/>"
               & ASCII.LF
               & "  <metadata key=""extruder"" value=""4""/>"
               & ASCII.LF
               & Part ("2", "white back", "4")
               & Part ("3", "cyan", "1")
               & Part ("4", "yellow", "3")
               & Part ("5", "white", "4")
               & " </object>"),
            "unexpected filaments of the parts: " & Settings);
         Assert
           (Contains
              (To_String (Files (1).Data), "<Default Extension=""config"""),
            "the content type of the settings is not declared");
      end;

      --  Width and height are scaled as for a plain lithophane (5 x 4
      --  units), and the depth is the one of the white part alone: the
      --  white sheet comes on top of it (the ink does not, it lies under a
      --  low point of the relief).
      Size := Bounding_Box (Read_3MF (Scratch ("parts.3mf")));
      Assert_Near (Size.Max.px - Size.Min.px, 50.0, "width", 1.0e-3);
      Assert_Near (Size.Max.py - Size.Min.py, 40.0, "height", 1.0e-3);
      Assert_Near (Size.Min.pz, 0.0, "bottom", 1.0e-3);
      Assert_Near (Size.Max.pz, 4.0 + Back_Thickness, "top", 1.0e-3);
   end File_Of_Parts;

   overriding
   procedure Register_Tests (T : in out Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Split_Of_A_Pixel'Access, "a pixel split into inks and black");
      Register_Routine
        (T,
         Picture_Without_Colour'Access,
         "without ink only the white part is left");
      Register_Routine
        (T, Layers_Are_Stacked'Access, "the parts lie on one another");
      Register_Routine
        (T, Ink_In_One_Place'Access, "an ink layer only where the ink is");
      Register_Routine
        (T, No_Pinched_Edge'Access, "no edge bounds four triangles");
      Register_Routine
        (T,
         Depth_Is_For_The_White_Part'Access,
         "a depth scales the white part only");
      Register_Routine
        (T,
         Inks_Of_Another_Size'Access,
         "inks that do not match the height map");
      Register_Routine
        (T, File_Of_Parts'Access, "3MF file made of coloured parts");
   end Register_Tests;

end Colour_Tests;
