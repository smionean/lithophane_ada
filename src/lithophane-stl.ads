------------------------------------------------------------------------------
--  lithophane-stl.ads
--
--  Specification of Lithophane.STL: write a facet list to an STL file,
--  either as text (Dump_STL_ASCII) or as the packed binary form
--  (Dump_STL_BIN). STL carries no unit information; the geometry is emitted
--  as-is in the coordinate space produced by Calculate_Facets.
--
--  Created : 2026-08-23
--  Author  : Simon Beàn
------------------------------------------------------------------------------

package Lithophane.STL is

   procedure Dump_STL_ASCII
     (Facets_List : Facets.Vector; Settings : Settings_Record);
   procedure Dump_STL_BIN
     (Facets_List : Facets.Vector; Settings : Settings_Record);

end Lithophane.STL;
