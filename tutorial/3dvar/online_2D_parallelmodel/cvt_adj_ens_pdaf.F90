!> Apply adjoint ensemble covariance operator to a state vector
!!
!! User-supplied call-back routine for PDAF.
!!
!! Used in 3D Ensemble Var and Hybrid 3D-Var.
!!
!! The routine is called during the analysis step of
!! ensemble 3D-Var or hybrid 3D-Var. It has to apply
!! the adjoint ensemble covariance operator (square
!! root of B) to a vector in control space.
!!
!! For domain decomposition, the action is for
!! the PE-local sub-domain of the state. Thus the
!! covariance operator is applied to a sub-state.
!! In addition the control vector can also be 
!! distributed (in case of type_opt=12 or 13).
!!
!! This code variant uses an explicit array holding
!! the covariance operator as a matrix.
!!
!! __Revision history:__
!! * 2021-03 - Lars Nerger - Initial code
!! * Later revisions - see repository log
!!
SUBROUTINE cvt_adj_ens_pdaf(iter, dim_p, dim_ens, dim_cvec_ens_p, ens_p, Vv_p, v_p)

  USE mpi                     ! MPI
  USE mod_assimilation, &     ! Assimilation variables
       ONLY: Vmat_ens_p, dim_cvec_ens, off_cv_ens_p, type_opt
  USE mod_parallel_pdaf, &    ! PDAF parallelization variables
       ONLY: COMM_filter, MPIerr, mype_filter

  IMPLICIT NONE

! *** Arguments ***
  INTEGER, INTENT(in) :: iter                 !< Iteration of optimization
  INTEGER, INTENT(in) :: dim_p                !< PE-local dimension of state
  INTEGER, INTENT(in) :: dim_ens              !< Ensemble size
  INTEGER, INTENT(in) :: dim_cvec_ens_p       !< PE-local dimension of control vector
  REAL, INTENT(in) :: ens_p(dim_p, dim_ens)   !< PE-local ensemble
  REAL, INTENT(in)    :: Vv_p(dim_p)          !< PE-local input vector
  REAL, INTENT(inout) :: v_p(dim_cvec_ens_p)  !< PE-local result vector

! *** local variables ***
  INTEGER :: i                       ! Counter
  REAL, ALLOCATABLE :: v_g(:)        ! Global control vector
  REAL, ALLOCATABLE :: v_g_part(:)   ! Global control vector (partial sums)


! ***************************************************
! *** Apply covariance operator to a state vector ***
! *** by computing Vmat^T Vv_p                    ***
! *** Here, Vmat is represented by the ensemble   ***
! ***************************************************

  ALLOCATE(v_g_part(dim_cvec_ens))

  IF (type_opt==12 .OR. type_opt==13) THEN

     ! For the domain-decomposed solvers

     ! Initialize distributed vector on control space
     ALLOCATE(v_g(dim_cvec_ens))

     ! Transform control variable to state increment 
     ! - global vector of partial sums
     CALL dgemv('t', dim_p, dim_cvec_ens, 1.0, Vmat_ens_p, &
          dim_p, Vv_p, 1, 0.0, v_g_part, 1)

     ! Get global vector with global sums
     CALL MPI_Allreduce(v_g_part, v_g, dim_cvec_ens, MPI_REAL8, MPI_SUM, &
          COMM_filter, MPIerr)
     
     ! Select PE-local part of control vector
     DO i = 1, dim_cvec_ens_p
        v_p(i) = v_g(i + off_cv_ens_p(mype_filter+1))
     END DO

     DEALLOCATE(v_g)

  ELSE

     ! Without domain-decomposition

     ! Transform control variable to state increment
     CALL dgemv('t', dim_p, dim_cvec_ens_p, 1.0, Vmat_ens_p, &
          dim_p, Vv_p, 1, 0.0, v_g_part, 1)

     ! Get global vector with global sums
     CALL MPI_Allreduce(v_g_part, v_p, dim_cvec_ens, MPI_REAL8, MPI_SUM, &
          COMM_filter, MPIerr)

  END IF


! *** Clean up ***

  DEALLOCATE(v_g_part)

END SUBROUTINE cvt_adj_ens_pdaf
