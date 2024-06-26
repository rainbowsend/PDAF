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
! !ROUTINE: PDAF_lenkf_update --- Control analysis update of the local EnKF
!
! !INTERFACE:
SUBROUTINE  PDAF_lenkf_update(step, dim_p, dim_obs_p, dim_ens, state_p, &
     ens_p, rank_ana, U_init_dim_obs, U_obs_op, &
     U_add_obs_err, U_init_obs, U_init_obs_covar, U_prepoststep, U_localize, &
     screen, subtype, flag)

! !DESCRIPTION:
! Routine to control the analysis update of the localized EnKF.
! 
! The analysis is performed by calling PDAF\_lenkf\_analysis.
! In addition, the routine U\_prepoststep is called before
! and after the analysis to allow the user to access the 
! ensemble information.
!
! !  This is a core routine of PDAF and
!    should not be changed by the user   !
!
! !REVISION HISTORY:
! 2015-12 - Lars Nerger - Initial code by copying and adapting PDAF_enkf_update
! Later revisions - see svn log
!
! !USES:
  USE PDAF_timer, &
       ONLY: PDAF_timeit, PDAF_time_temp
  USE PDAF_memcounting, &
       ONLY: PDAF_memcount
  USE PDAF_mod_filtermpi, &
       ONLY: mype, dim_ens_l
  USE PDAF_mod_filter, &
       ONLY: forget, debug

  IMPLICIT NONE

! !ARGUMENTS:
  INTEGER, INTENT(in) :: step       ! Current time step
  INTEGER, INTENT(in) :: dim_p      ! PE-local dimension of model state
  INTEGER, INTENT(out) :: dim_obs_p ! PE-local dimension of observation vector
  INTEGER, INTENT(in) :: dim_ens    ! Size of state ensemble
  INTEGER, INTENT(in) :: rank_ana   ! Rank to be considered for inversion of HPH
  REAL, INTENT(inout) :: state_p(dim_p)        ! PE-local model state
  REAL, INTENT(inout) :: ens_p(dim_p, dim_ens) ! PE-local state ensemble
  INTEGER, INTENT(in) :: screen     ! Verbosity flag
  INTEGER, INTENT(in) :: subtype    ! Specification of filter subtype
  INTEGER, INTENT(inout) :: flag    ! Status flag

! ! External subroutines 
! ! (PDAF-internal names, real names are defined in the call to PDAF)
  EXTERNAL :: U_init_dim_obs, & ! Initialize dimension of observation vector
       U_obs_op, &              ! Observation operator
       U_init_obs, &            ! Initialize observation vector
       U_init_obs_covar, &      ! Initialize observation error covariance matrix
       U_prepoststep, &         ! User supplied pre/poststep routine
       U_add_obs_err, &         ! Add observation error covariance matrix
       U_localize               ! Apply localization to HP and HPH^T

! !CALLING SEQUENCE:
! Called by: PDAF_put_state_lenkf
! Calls: U_prepoststep
! Calls: PDAF_lenkf_analysis_rsm
! Calls: PDAF_timeit
! Calls: PDAF_time_temp
!EOP

! *** local variables ***
  INTEGER :: i         ! Counters
  INTEGER :: minusStep ! Time step counter
  INTEGER, SAVE :: allocflag = 0     ! Flag whether first time allocation is done
  REAL :: Uinv(1, 1)   ! Unused array, but required in call to U_prepoststep


! **********************
! ***  Update phase  ***
! **********************

  IF (debug>0) THEN
  WRITE (*,*) '++ PDAF-debug: ', debug, 'PDAF_lenkf_update -- START'
     DO i = 1, dim_ens
        WRITE (*,*) '++ PDAF-debug PDAF_lenkf_update:', debug, 'ensemble member', i, &
             ' forecast values (1:min(dim_p,6)):', ens_p(1:min(dim_p,6),i)
     END DO
  END IF

! *** prestep for forecast modes and state ***
  CALL PDAF_timeit(5, 'new')
  minusStep = -step  ! Indicate forecast by negative time step number
  IF (mype == 0 .AND. screen > 0) THEN
     WRITE (*, '(a, 5x, a, i7)') 'PDAF', 'Call pre-post routine after forecast; step ', step
  ENDIF
  CALL U_prepoststep(minusStep, dim_p, dim_ens, dim_ens_l, dim_obs_p, &
       state_p, Uinv, ens_p, flag)
  CALL PDAF_timeit(5, 'old')

  IF (mype == 0 .AND. screen > 0) THEN
     IF (screen > 1) THEN
        WRITE (*, '(a, 5x, a, F10.3, 1x, a)') &
             'PDAF', '--- duration of prestep:', PDAF_time_temp(5), 's'
     END IF
     WRITE (*, '(a, 55a)') 'PDAF Analysis ', ('-', i = 1, 55)
  END IF

#ifndef PDAF_NO_UPDATE
  CALL PDAF_timeit(3, 'new')

  IF (debug>0) THEN
     WRITE (*,*) '++ PDAF-debug PDAF_lenkf_update', debug, &
          'Configuration: param_int(3) rank_ana_enkf', rank_ana

     WRITE (*,*) '++ PDAF-debug PDAF_lenkf_update', debug, &
          'Configuration: param_real(1) forget     ', forget
  END IF

  IF (subtype == 0) THEN
     ! *** analysis with representer method with 2m<n ***
     CALL PDAF_lenkf_analysis_rsm(step, dim_p, dim_obs_p, dim_ens, rank_ana, &
          state_p, ens_p, forget, U_init_dim_obs, U_obs_op, &
          U_add_obs_err, U_init_obs, U_init_obs_covar, U_localize, screen, flag)
  END IF

  IF (debug>0) THEN
     DO i = 1, dim_ens
        WRITE (*,*) '++ PDAF-debug PDAF_lenkf_update:', debug, 'ensemble member', i, &
             ' analysis values (1:min(dim_p,6)):', ens_p(1:min(dim_p,6),i)
     END DO
  END IF

  IF (debug>0) &
       WRITE (*,*) '++ PDAF-debug: ', debug, 'PDAF_lenkf_update -- exit analysis function'

  CALL PDAF_timeit(3, 'old')

  IF (mype == 0 .AND. screen > 1) THEN
     WRITE (*, '(a, 5x, a, F10.3, 1x, a)') &
          'PDAF', '--- update duration:', PDAF_time_temp(3), 's'
  END IF

#else
  WRITE (*,'(/5x,a/)') &
       '!!! PDAF WARNING: ANALYSIS STEP IS DEACTIVATED BY PDAF_NO_UPDATE !!!'
#endif

! *** poststep for analysis ensemble ***
  CALL PDAF_timeit(5, 'new')
  IF (mype == 0 .AND. screen > 0) THEN
     WRITE (*, '(a, 5x, a)') 'PDAF', 'Call pre-post routine after analysis step'
  ENDIF
  CALL U_prepoststep(step, dim_p, dim_ens, dim_ens_l, dim_obs_p, &
       state_p, Uinv, ens_p, flag)
  CALL PDAF_timeit(5, 'old')
  
  IF (mype == 0 .AND. screen > 0) THEN
     IF (screen > 1) THEN
        WRITE (*, '(a, 5x, a, F10.3, 1x, a)') &
             'PDAF', '--- duration of poststep:', PDAF_time_temp(5), 's'
     END IF
     WRITE (*, '(a, 55a)') 'PDAF Forecast ', ('-', i = 1, 55)
  END IF


! ********************
! *** Finishing up ***
! ********************

  IF (allocflag == 0) allocflag = 1

  IF (debug>0) &
       WRITE (*,*) '++ PDAF-debug: ', debug, 'PDAF_lenkf_update -- END'

END SUBROUTINE PDAF_lenkf_update
