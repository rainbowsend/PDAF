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
! !ROUTINE: PDAF_hyb3dvar_analysis_cvt --- hybrid 3DVAR with CVT
!
! !INTERFACE:
SUBROUTINE PDAF_hyb3dvar_analysis_cvt(step, dim_p, dim_obs_p, dim_ens, &
     dim_cvec, dim_cvec_ens, state_p, ens_p, state_inc_p, &
     U_init_dim_obs, U_obs_op, U_init_obs, U_prodRinvA, &
     U_cvt, U_cvt_adj, U_cvt_ens, U_cvt_adj_ens, U_obs_op_lin, U_obs_op_adj, &
     screen, incremental, type_opt, flag)

! !DESCRIPTION:
! Analysis step of incremental hybrid 3DVAR with control
! variable transformation.
!
! Variant for domain decomposed states.
!
! !  This is a core routine of PDAF and
!    should not be changed by the user   !
!
! !REVISION HISTORY:
! 2021-03 - Lars Nerger - Initial code
! Later revisions - see svn log
!
! !USES:
! Include definitions for real type of different precision
! (Defines BLAS/LAPACK routines and MPI_REALTYPE)
#include "typedefs.h"

  USE PDAF_timer, &
       ONLY: PDAF_timeit
  USE PDAF_memcounting, &
       ONLY: PDAF_memcount
  USE PDAF_mod_filtermpi, &
       ONLY: mype
  USE PDAF_mod_filter, &
       ONLY: obs_member, beta_3dvar, debug
  USE PDAFomi, &
       ONLY: omi_omit_obs => omit_obs

  IMPLICIT NONE

! !ARGUMENTS:
  INTEGER, INTENT(in) :: step         ! Current time step
  INTEGER, INTENT(in) :: dim_p        ! PE-local dimension of model state
  INTEGER, INTENT(out) :: dim_obs_p   ! PE-local dimension of observation vector
  INTEGER, INTENT(in) :: dim_ens      ! Size of ensemble
  INTEGER, INTENT(in) :: dim_cvec                ! Size of control vector (parameterized part)
  INTEGER, INTENT(in) :: dim_cvec_ens            ! Size of control vector (ensemble part)
  REAL, INTENT(out)   :: state_p(dim_p)          ! on exit: PE-local forecast state
  REAL, INTENT(inout) :: ens_p(dim_p, dim_ens)   ! PE-local state ensemble
  REAL, INTENT(inout) :: state_inc_p(dim_p)      ! PE-local state analysis increment
  INTEGER, INTENT(in) :: screen       ! Verbosity flag
  INTEGER, INTENT(in) :: incremental  ! Control incremental updating
  INTEGER, INTENT(in) :: type_opt     ! Type of minimizer for 3DVar
  INTEGER, INTENT(inout) :: flag      ! Status flag

! ! External subroutines 
! ! (PDAF-internal names, real names are defined in the call to PDAF)
  EXTERNAL :: U_init_dim_obs, & ! Initialize dimension of observation vector
       U_obs_op, &              ! Observation operator
       U_init_obs, &            ! Initialize observation vector
       U_prodRinvA, &           ! Provide product R^-1 A
       U_cvt, &                 ! Apply control vector transform matrix to control vector (parameterized)
       U_cvt_adj, &             ! Apply adjoint control vector transform matrix (parameterized)
       U_cvt_ens, &             ! Apply control vector transform matrix to control vector (ensemble)
       U_cvt_adj_ens, &         ! Apply adjoint control vector transform matrix (ensemble
       U_obs_op_lin, &          ! Linearized observation operator
       U_obs_op_adj             ! Adjoint observation operator

! !CALLING SEQUENCE:
! Called by: PDAF_hyb3dvar_update_estkf
! Called by: PDAF_hyb3dvar_update_lestkf
! Calls: U_init_dim_obs
! Calls: U_obs_op
! Calls: U_init_obs
! Calls: PDAF_timeit
! Calls: PDAF_memcount
!EOP

! *** local variables ***
  INTEGER :: member, row               ! Counters
  INTEGER, SAVE :: allocflag = 0       ! Flag whether first time allocation is done
  REAL :: invdimens                    ! Inverse global ensemble size
  REAL, ALLOCATABLE :: obs_p(:)        ! PE-local observation vector
  REAL, ALLOCATABLE :: dy_p(:)         ! PE-local observation background residual
  REAL, ALLOCATABLE :: v_par_p(:)      ! PE-local analysis increment control vector (parameterized)
  REAL, ALLOCATABLE :: v_ens_p(:)      ! PE-local analysis increment control vector (ensemble)
  REAL, ALLOCATABLE :: state_inc_ens_p(:) ! State increment for ensmeble part
  INTEGER :: opt_parallel              ! Whether to run solver with decomposed control vector
 

! **********************
! *** INITIALIZATION ***
! **********************

  IF (debug>0) &
       WRITE (*,*) '++ PDAF-debug: ', debug, 'PDAF_hyb3dvar_analysis -- START'

  IF (mype == 0 .AND. screen > 0) THEN
     WRITE (*, '(a,5x,a)') 'PDAF','Step 1: Update state estimate with variational solver'
     WRITE (*, '(a,5x,a, f10.3)') 'PDAF','--- hybrid weight: ', beta_3dvar
     IF (type_opt==1) THEN
        WRITE (*, '(a, 5x, a)') 'PDAF', '--- solver: LBFGS' 
     ELSEIF (type_opt==2) THEN
        WRITE (*, '(a, 5x, a)') 'PDAF', '--- solver: CG+' 
     ELSEIF (type_opt==3) THEN
        WRITE (*, '(a, 5x, a)') 'PDAF', '--- solver: plain CG' 
     ELSEIF (type_opt==12) THEN
        WRITE (*, '(a, 5x, a)') 'PDAF', '--- solver: CG+ parallelized' 
     ELSEIF (type_opt==13) THEN
        WRITE (*, '(a, 5x, a)') 'PDAF', '--- solver: plain CG parallelized' 
     END IF
  END IF


! ***********************************
! *** Compute mean forecast state ***
! ***********************************

  CALL PDAF_timeit(11, 'new')

  state_p = 0.0
  invdimens = 1.0 / REAL(dim_ens)
  DO member = 1, dim_ens
     DO row = 1, dim_p
        state_p(row) = state_p(row) + invdimens * ens_p(row, member)
     END DO
  END DO

  IF (debug>0) THEN
        WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
             'forecast ensemble mean (1:min(dim_p,6)):', state_p(1:min(dim_p,6))
  END IF
  
  CALL PDAF_timeit(11, 'old')


! *********************************
! *** Get observation dimension ***
! *********************************

  IF (debug>0) THEN
     WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, '  dim_p', dim_p
     IF (incremental<2) &
          WRITE (*,*) '++ PDAF-debug: ', debug, 'PDAF_hyb3dvar_analysis -- call init_dim_obs'
  END IF

  CALL PDAF_timeit(43, 'new')
  CALL U_init_dim_obs(step, dim_obs_p)
  CALL PDAF_timeit(43, 'old')
  
  IF (debug>0) &
       WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, '  dim_obs_p', dim_obs_p
  
  IF (screen > 2) THEN
     WRITE (*, '(a, 5x, a13, 1x, i6, 1x, a, i10)') &
          'PDAF', '--- PE-domain', mype, 'dimension of observation vector', dim_obs_p
  END IF


  haveobsB: IF (dim_obs_p > 0) THEN

! *******************************
! *** Background innovation   ***
! ***      d = y - H xb       ***
! *******************************

     CALL PDAF_timeit(12, 'new')
  
     ! *** Observation background innovation ***

     ! Get observed state estimate
     ALLOCATE(dy_p(dim_obs_p))
     IF (allocflag == 0) CALL PDAF_memcount(3, 'r', dim_obs_p)

     IF (debug>0) &
          WRITE (*,*) '++ PDAF-debug: ', debug, 'PDAF_hyb3dvar_analysis -- call obs_op'

     obs_member = 0 ! Store member index (0 for central state)
     CALL PDAF_timeit(44, 'new')
     CALL U_obs_op(step, dim_p, dim_obs_p, state_p, dy_p)
     CALL PDAF_timeit(44, 'old')

     ! get observation vector
     ALLOCATE(obs_p(dim_obs_p))
     IF (allocflag == 0) CALL PDAF_memcount(3, 'r', dim_obs_p)

     IF (debug>0) &
          WRITE (*,*) '++ PDAF-debug: ', debug, 'PDAF_hyb3dvar_analysis -- call init_obs'

     CALL PDAF_timeit(50, 'new')
     CALL U_init_obs(step, dim_obs_p, obs_p)
     CALL PDAF_timeit(50, 'old')

     ! Get residual as difference of observation and observed state
     CALL PDAF_timeit(51, 'new')
     dy_p = obs_p - dy_p
     CALL PDAF_timeit(51, 'old')

     IF (debug>0) THEN
        WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
             'innovation d(1:min(dim_obs_p,6))', dy_p(1:min(dim_p,6))
        WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
             'MIN/MAX of innovation', MINVAL(dy_p), MAXVAL(dy_p)
     END IF

     ! Omit observations with too high innovation
     IF (omi_omit_obs)  THEN
        CALL PDAF_timeit(51, 'new')
        CALL PDAFomi_omit_by_inno_cb(dim_obs_p, dy_p, obs_p)
        CALL PDAF_timeit(51, 'old')
     END IF

     CALL PDAF_timeit(12, 'old')


! ****************************
! ***   Iterative solving  ***
! ****************************

     CALL PDAF_timeit(52, 'new')

     opt_parallel = 0

     ! Prepare control vectors for optimization
     IF (dim_cvec_ens>0) THEN
        ALLOCATE(v_ens_p(dim_cvec_ens))
     ELSE
        ALLOCATE(v_ens_p(1))
     END IF
     IF (dim_cvec>0) THEN
        ALLOCATE(v_par_p(dim_cvec))
     ELSE
        ALLOCATE(v_par_p(1))
     END IF
     IF (allocflag == 0) CALL PDAF_memcount(3, 'r', dim_cvec_ens + dim_cvec)
     v_par_p = 0.0
     v_ens_p = 0.0

     ! Choose solver
     opt: IF (type_opt==1) THEN

        ! LBFGS solver
        CALL PDAF_hyb3dvar_optim_lbfgs(step, dim_p, dim_ens, dim_cvec, dim_cvec_ens, &
             dim_obs_p, ens_p, obs_p, dy_p, v_par_p, v_ens_p, U_prodRinvA, &
             U_cvt, U_cvt_adj, U_cvt_ens, U_cvt_adj_ens, U_obs_op_lin, U_obs_op_adj, &
             opt_parallel, beta_3dvar, screen)

     ELSEIF (type_opt==2 .OR. type_opt==12) THEN

        IF (type_opt==12) opt_parallel = 1

        ! CG+ solver
        CALL PDAF_hyb3dvar_optim_cgplus(step, dim_p, dim_ens, dim_cvec, dim_cvec_ens, &
             dim_obs_p, ens_p, obs_p, dy_p, v_par_p, v_ens_p, U_prodRinvA, &
             U_cvt, U_cvt_adj, U_cvt_ens, U_cvt_adj_ens, U_obs_op_lin, U_obs_op_adj, &
             opt_parallel, beta_3dvar, screen)

     ELSEIF (type_opt==3 .OR. type_opt==13) THEN

        IF (type_opt==13) opt_parallel = 1

        ! CG solver
        CALL PDAF_hyb3dvar_optim_cg(step, dim_p, dim_ens, dim_cvec, dim_cvec_ens, &
             dim_obs_p, ens_p, obs_p, dy_p, v_par_p, v_ens_p, U_prodRinvA, &
             U_cvt, U_cvt_adj, U_cvt_ens, U_cvt_adj_ens, U_obs_op_lin, U_obs_op_adj, &
             opt_parallel, beta_3dvar, screen)

     ELSE
        ! Further solvers - not implemented
        WRITE (*,'(a)') 'PDAF-ERROR: Invalid solver chosen!'
        flag=10
     END IF opt

     CALL PDAF_timeit(52, 'old')


! ****************************************************
! ***   Solving completed: Compute state increment ***
! ****************************************************

     CALL PDAF_timeit(14, 'new')

     ! Apply V to control vector v_ens_p
     state_inc_p = 0.0
     IF (dim_cvec>0) THEN
        IF (debug>0) THEN
           WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
                'control vector parameterized part (1:min(dim_p,6))', v_par_p(1:min(dim_p,6))
           WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
                'MIN/MAX of control vector parameterized part', MINVAL(v_par_p), MAXVAL(v_par_p)
           WRITE (*,*) '++ PDAF-debug: ', debug, &
                'PDAF_hyb3dvar_analysis -- call cvt for final state increment'
        END IF

        CALL PDAF_timeit(49, 'new')
        CALL U_cvt(0, dim_p, dim_cvec, v_par_p, state_inc_p)
        CALL PDAF_timeit(49, 'old')
        CALL PDAF_timeit(51, 'new')
        state_inc_p = SQRT(1.0-beta_3dvar)*state_inc_p
        CALL PDAF_timeit(51, 'old')

        IF (debug>0) THEN
           WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
                'state increment parameterized (1:min(dim_cvec,6))', state_inc_p(1:min(dim_cvec,6))
           WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
                'MIN/MAX of increment parameterized', MINVAL(state_inc_p), MAXVAL(state_inc_p)
        END IF
     END IF
     IF (dim_cvec_ens>0) THEN
        IF (debug>0) THEN
           WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
                'control vector ensemble part (1:min(dim_p,6))', v_ens_p(1:min(dim_p,6))
           WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
                'MIN/MAX of control vector ensemble part', MINVAL(v_ens_p), MAXVAL(v_ens_p)
             WRITE (*,*) '++ PDAF-debug: ', debug, &
             'PDAF_hyb3dvar_analysis -- call cvt_ens for final state increment'
        END IF

        CALL PDAF_timeit(22, 'new')

        ALLOCATE(state_inc_ens_p(dim_p))
        CALL U_cvt_ens(0, dim_p, dim_ens, dim_cvec_ens, &
             ens_p, v_ens_p, state_inc_ens_p)
        CALL PDAF_timeit(22, 'old')
        IF (debug>0) THEN
           WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
                'state increment ensemble (1:min(dim_cvec_ens,6))', state_inc_ens_p(1:min(dim_cvec_ens,6))
           WRITE (*,*) '++ PDAF-debug PDAF_hyb3dvar_analysis:', debug, &
                'MIN/MAX of increment ensemble', MINVAL(state_inc_ens_p), MAXVAL(state_inc_p)
        END IF

        CALL PDAF_timeit(51, 'new')
        state_inc_p = state_inc_p + SQRT(beta_3dvar)*state_inc_ens_p
        CALL PDAF_timeit(51, 'old')

        DEALLOCATE(state_inc_ens_p)
     END IF

     CALL PDAF_timeit(51, 'new')
     IF (incremental<1) THEN
        ! Add analysis increment to state vector
        state_p = state_p + state_inc_p

        ! Add analysis state to ensemble perturbations
        DO member = 1, dim_ens
           DO row = 1, dim_p
              ens_p(row, member) = ens_p(row, member) + state_inc_p(row)
           END DO
        END DO
     END IF
     CALL PDAF_timeit(51, 'old')

     CALL PDAF_timeit(14, 'old')

  END IF haveobsB


! ********************
! *** Finishing up ***
! ********************

  IF (dim_obs_p > 0) THEN
     DEALLOCATE(obs_p, dy_p)
     DEALLOCATE(v_ens_p)
     DEALLOCATE(v_par_p)
  END IF

  IF (allocflag == 0) allocflag = 1

  IF (debug>0) &
       WRITE (*,*) '++ PDAF-debug: ', debug, 'PDAF_hyb3dvar_analysis -- END'

END SUBROUTINE PDAF_hyb3dvar_analysis_cvt
