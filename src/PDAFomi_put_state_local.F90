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
! !ROUTINE: PDAFomi_put_state_local --- Interface to PDAF for domain-local filters
!
! !INTERFACE:
SUBROUTINE PDAFomi_put_state_local(collect_state_pdaf, init_dim_obs_f_pdaf, obs_op_f_pdaf, &
     prepoststep_pdaf, init_n_domains_pdaf, init_dim_l_pdaf, init_dim_obs_l_pdaf, &
     g2l_state_pdaf, l2g_state_pdaf, outflag)

! !DESCRIPTION:
! Interface routine called from the model during the 
! forecast of each ensemble state to transfer data
! from the model to PDAF and to perform the analysis
! step.
!
! This routine provides the simplified interface
! where names of user-provided subroutines are
! fixed. It simply calls the routine with the
! full interface using pre-defined routine names.
!
! The routine supports all domain-localized filters.
!
! !  This is a core routine of PDAF and
!    should not be changed by the user   !
!
! !REVISION HISTORY:
! 2020-11 - Lars Nerger - Initial code
! Later revisions - see svn log
!
! !USES:
  USE PDAF_mod_filter, ONLY: filterstr
  USE PDAFomi, ONLY: PDAFomi_dealloc

  IMPLICIT NONE
  
! !ARGUMENTS:
  INTEGER, INTENT(inout) :: outflag ! Status flag
  
! ! Names of external subroutines 
  EXTERNAL :: collect_state_pdaf, &    ! Routine to collect a state vector
       prepoststep_pdaf                ! User supplied pre/poststep routine
  EXTERNAL :: init_n_domains_pdaf, &   ! Provide number of local analysis domains
       init_dim_l_pdaf, &              ! Init state dimension for local ana. domain
       g2l_state_pdaf, &               ! Get state on local ana. domain from full state
       l2g_state_pdaf, &               ! Init full state from local state
       init_dim_obs_f_pdaf, &          ! Initialize dimension of full observation vector
       obs_op_f_pdaf, &                ! Full observation operator
       init_dim_obs_l_pdaf             ! Initialize local dimimension of obs. vector
  EXTERNAL :: PDAFomi_init_obs_f_cb, & ! Initialize full observation vector
       PDAFomi_init_obs_l_cb, &        ! Initialize local observation vector
       PDAFomi_init_obsvar_cb, &       ! Initialize mean observation error variance
       PDAFomi_init_obsvar_l_cb, &     ! Initialize local mean observation error variance
       PDAFomi_g2l_obs_cb, &           ! Restrict full obs. vector to local analysis domain
       PDAFomi_prodRinvA_l_cb, &       ! Provide product R^-1 A on local analysis domain
       PDAFomi_likelihood_l_cb         ! Compute likelihood and apply localization
  EXTERNAL :: PDAFomi_prodRinvA_hyb_l_cb, &  ! Product R^-1 A on local analysis domain with hybrid weight
       PDAFomi_likelihood_hyb_l_cb     ! Compute likelihood and apply localization with tempering

! !CALLING SEQUENCE:
! Called by: model code  
!EOP


! **************************************************
! *** Call the full put_state interface routine  ***
! **************************************************

  IF (TRIM(filterstr) == 'LSEIK') THEN
     CALL PDAF_put_state_lseik(collect_state_pdaf, init_dim_obs_f_pdaf, obs_op_f_pdaf, &
          PDAFomi_init_obs_f_cb, PDAFomi_init_obs_l_cb, prepoststep_pdaf, &
          PDAFomi_prodRinvA_l_cb, init_n_domains_pdaf, init_dim_l_pdaf, init_dim_obs_l_pdaf, &
          g2l_state_pdaf, l2g_state_pdaf, PDAFomi_g2l_obs_cb, PDAFomi_init_obsvar_cb, &
          PDAFomi_init_obsvar_l_cb, outflag)
  ELSE IF (TRIM(filterstr) == 'LETKF') THEN
     CALL PDAF_put_state_letkf(collect_state_pdaf, init_dim_obs_f_pdaf, obs_op_f_pdaf, &
          PDAFomi_init_obs_f_cb, PDAFomi_init_obs_l_cb, prepoststep_pdaf, &
          PDAFomi_prodRinvA_l_cb, init_n_domains_pdaf, init_dim_l_pdaf, init_dim_obs_l_pdaf, &
          g2l_state_pdaf, l2g_state_pdaf, PDAFomi_g2l_obs_cb, PDAFomi_init_obsvar_cb, &
          PDAFomi_init_obsvar_l_cb, outflag)
  ELSE IF (TRIM(filterstr) == 'LESTKF') THEN
     CALL PDAF_put_state_lestkf(collect_state_pdaf, init_dim_obs_f_pdaf, obs_op_f_pdaf, &
          PDAFomi_init_obs_f_cb, PDAFomi_init_obs_l_cb, prepoststep_pdaf, &
          PDAFomi_prodRinvA_l_cb, init_n_domains_pdaf, init_dim_l_pdaf, init_dim_obs_l_pdaf, &
          g2l_state_pdaf, l2g_state_pdaf, PDAFomi_g2l_obs_cb, PDAFomi_init_obsvar_cb, &
          PDAFomi_init_obsvar_l_cb, outflag)
  ELSE IF (TRIM(filterstr) == 'LNETF') THEN
     CALL PDAF_put_state_lnetf(collect_state_pdaf, init_dim_obs_f_pdaf, obs_op_f_pdaf, &
          PDAFomi_init_obs_l_cb, prepoststep_pdaf, PDAFomi_likelihood_l_cb, init_n_domains_pdaf, &
          init_dim_l_pdaf, init_dim_obs_l_pdaf, g2l_state_pdaf, l2g_state_pdaf, &
          PDAFomi_g2l_obs_cb, outflag)
  ELSE IF (TRIM(filterstr) == 'LKNETF') THEN
     CALL PDAF_put_state_lknetf(collect_state_pdaf, init_dim_obs_f_pdaf, obs_op_f_pdaf, &
          PDAFomi_init_obs_f_cb, PDAFomi_init_obs_l_cb, prepoststep_pdaf, &
          PDAFomi_prodRinvA_l_cb, PDAFomi_prodRinvA_hyb_l_cb, &
          init_n_domains_pdaf, init_dim_l_pdaf, init_dim_obs_l_pdaf, &
          g2l_state_pdaf, l2g_state_pdaf, PDAFomi_g2l_obs_cb, PDAFomi_init_obsvar_cb, &
          PDAFomi_init_obsvar_l_cb, PDAFomi_likelihood_l_cb, PDAFomi_likelihood_hyb_l_cb, outflag)
  END IF


! *******************************************
! *** Deallocate and re-init observations ***
! *******************************************

  CALL PDAFomi_dealloc()

END SUBROUTINE PDAFomi_put_state_local
