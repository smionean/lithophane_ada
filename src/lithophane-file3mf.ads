------------------------------------------------------------------------------
--  lithophane-file3mf.ads
--
--  Specification of Lithophane.File3mf: write the triangulated lithophane
--  geometry to a 3MF file (an OPC/ZIP package written with the "stored"
--  method, so no external compression library is needed). The mesh is a
--  closed solid (coincident vertices are welded) and can be scaled to a
--  requested physical size in millimetres.
--
--  Created : 2026-09-02
--  Author  : Simon Beàn & Claude Code
------------------------------------------------------------------------------

package Lithophane.File3mf is

   --  Write the triangulated geometry held in Facets_List to a 3MF file
   --  named "<Settings.outfilename>.3mf".
   --
   --  A 3MF file is an OPC (ZIP) package holding three parts:
   --    * [Content_Types].xml
   --    * _rels/.rels
   --    * 3D/3dmodel.model   (the mesh, as XML)
   --  The archive is produced here with the "stored" (uncompressed) method,
   --  so no external ZIP/deflate library is required.
   --
   --  Coincident facet corners are welded onto shared vertex indices so the
   --  mesh is a closed manifold (no "open edges" in a slicer).
   --
   --  If Settings.dimensions requests a physical size, the mesh is scaled so
   --  its bounding box matches: each axis with a non-zero value is scaled to
   --  it exactly, and an axis left at 0.0 follows the first constrained axis
   --  so the model keeps its proportions. 3MF is declared in millimetres.
   procedure Dump_3mf
     (Facets_List : Facets.Vector; Settings : Settings_Record);

end Lithophane.File3mf;
