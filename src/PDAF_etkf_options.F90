! Copyright (c) 2004-2024 Lars Nerger
!
! This file is part of PDAF.
!
! PDAF is free software: you can redistribute it and/or modify
! it under the terms of the GNU Lesser General Public License
! as published by the Free Software Foundation, either version
! 3 of the License, or (at your option) any later version.
!
! PDAF is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU Lesser General Public License for more details.
!
! You should have received a copy of the GNU Lesser General Public
! License along with PDAF.  If not, see <http://www.gnu.org/licenses/>.
!
!$Id$
!BOP
!
! !ROUTINE: PDAF_etkf_options --- Information output on options for ETKF
!
! !INTERFACE:
SUBROUTINE PDAF_etkf_options()

! !DESCRIPTION:
! Subroutine to perform information output on options
! available for the Ensemble Transform Kalman filter.

! !  This is a core routine of PDAF and
!    should not be changed by the user   !
!
! !REVISION HISTORY:
! 2011-08 - Lars Nerger - Initial code
! Later revisions - see svn log
!
! !USES:

  IMPLICIT NONE

! !CALLING SEQUENCE:
! Called by: PDAF_options_filters
!EOP
  
  WRITE(*, '(/a, 5x, a)') 'PDAF', '+++++++++++++++++++++++++++++++++++++++++++++++++++++++'
  WRITE(*, '(a, 5x, a)')  'PDAF', '+++     Ensemble Transform Kalman Filter (ETKF)     +++'
  WRITE(*, '(a, 5x, a)')  'PDAF', '+++                                                 +++'
  WRITE(*, '(a, 5x, a)')  'PDAF', '+++   Bishop et al., Mon. Wea. Rev. 129 (2001) 420  +++'
  WRITE(*, '(a, 5x, a)')  'PDAF', '+++    A symmetric square root is used following    +++'
  WRITE(*, '(a, 5x, a)')  'PDAF', '+++      Hunt et al. Physica D 230 (2007) 112       +++'
  WRITE(*, '(a, 5x, a)')  'PDAF', '+++++++++++++++++++++++++++++++++++++++++++++++++++++++'

  WRITE(*, '(/a, 5x, a)') 'PDAF', 'Available options for ETKF:'

  WRITE(*, '(a, 5x, a)') 'PDAF', '--- Sub-types (Parameter subtype) ---'
  WRITE(*, '(a, 7x, a)') &
       'PDAF', '0: full ensemble integration; apply T-matrix analogously to SEIK'
  WRITE(*, '(a, 7x, a)') 'PDAF', '1: full ensemble integration; formulation without T matrix'
  WRITE(*, '(a, 7x, a)') 'PDAF', '2: Fixed error space basis; analysis with T-matrix'
  WRITE(*, '(a, 7x, a)') 'PDAF', '3: Fixed state covariance matrix; analysis with T-matrix'
  WRITE(*, '(a, 7x, a)') 'PDAF', '5: Offline mode; analysis with T-matrix (deprecated, use PDAF_set_offline_mode)'

  WRITE(*, '(a, 5x, a)') 'PDAF', '--- Integer parameters (Array param_int) ---'
  WRITE(*, '(a, 7x, a)') 'PDAF', 'param_int(1): Dimension of state vector (>0), required'
  WRITE(*, '(a, 7x, a)') 'PDAF', 'param_int(2): Ensemble size (>0), required'
  WRITE(*, '(a, 7x, a)') 'PDAF', 'param_int(3): Size of smoothing lag (>=0), optional'
  WRITE(*, '(a, 11x, a)') 'PDAF', '0: no smoothing (default)'
  WRITE(*, '(a, 11x, a)') 'PDAF', '>0: apply smoother up to specified lag'
  WRITE(*, '(a, 7x, a)') &
       'PDAF', 'param_int(4): not used'
  WRITE(*, '(a, 7x, a)') &
       'PDAF', 'param_int(5): Type of forgetting factor; optional'
  WRITE(*, '(a, 11x, a)') 'PDAF', '0: fixed forgetting factor (default)'
  WRITE(*, '(a, 11x, a)') 'PDAF', '1: adaptive forgetting factor (experimental)'
  WRITE(*, '(a, 7x, a)') &
       'PDAF', 'param_int(6): Type of ensemble transformation matrix; optional'
  WRITE(*, '(a, 11x, a)') 'PDAF', '0: deterministic transformation (default)'
  WRITE(*, '(a, 11x, a)') &
       'PDAF', '2: use product of 0 with random orthonomal matrix with eigenvector (1,...,1)^T'
  WRITE(*, '(a, 7x, a)') &
       'PDAF', 'param_int(7): not used'
  WRITE(*, '(a, 7x, a)') &
       'PDAF', 'param_int(8): Application of observation operator H'
  WRITE(*, '(a, 11x, a)') 'PDAF', '0: Apply H to ensemble mean to compute residual (default)'
  WRITE(*, '(a, 11x, a)') 'PDAF', '1: Apply H to all ensemble states; then compute residual from mean of these'
  WRITE(*, '(a, 11x, a)') 'PDAF', '   param_int(8)=1 is the recomended choice for nonlinear H'


  WRITE(*, '(a, 5x, a)') 'PDAF', '--- Floating point parameters (Array param_real) ---'
  WRITE(*, '(a, 7x, a)') &
       'PDAF', 'param_real(1): Forgetting factor (usually >0 and <=1), required'

  WRITE(*, '(a, 5x, a)') 'PDAF', '--- Further parameters ---'
  WRITE(*, '(a, 7x, a)') 'PDAF', 'n_modeltasks: Number of parallel model integration tasks'
  WRITE(*, '(a, 11x, a)') &
       'PDAF', '>=1 for subtypes 0 and 1; not larger than total number of processors'
  WRITE(*, '(a, 11x, a)') 'PDAF', '=1 required for subtypes 2 and 3'
  WRITE(*, '(a, 7x, a)') 'PDAF', 'screen: Control verbosity of PDAF'
  WRITE(*, '(a, 11x, a)') 'PDAF', '0: no outputs'
  WRITE(*, '(a, 11x, a)') 'PDAF', '1: basic output (default)'
  WRITE(*, '(a, 11x, a)') 'PDAF', '2: 1 plus timing output'
  WRITE(*, '(a, 11x, a)') 'PDAF', '3: 2 plus debug output'

  WRITE(*, '(a, 5x, a)') &
       'PDAF', '+++++++++ End of option overview for the ETKF ++++++++++'
  
END SUBROUTINE PDAF_etkf_options
