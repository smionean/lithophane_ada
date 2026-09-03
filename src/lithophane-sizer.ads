------------------------------------------------------------------------------
--  lithophane-sizer.ads
--
--  Specification of Lithophane.Sizer: intended home for input-image
--  down-sizing (Resize) and for estimating how much the image can be
--  reduced (Evalute_Size_Reduction). Placeholder API, not wired in yet.
--
--  Created : 2026-08-23
--  Author  : Simon Beàn
------------------------------------------------------------------------------

package Lithophane.Sizer is
   procedure Resize;
   function Evalute_Size_Reduction return Integer;
end Lithophane.Sizer;