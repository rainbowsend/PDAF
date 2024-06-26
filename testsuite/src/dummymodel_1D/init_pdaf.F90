!$Id$
!BOP
!
! !ROUTINE: init_pdaf - Routine to prepare and call initialization of PDAF
!
! !INTERFACE:
SUBROUTINE init_pdaf()

! !DESCRIPTION:
! This routine collects the initialization of variables for PDAF.
! In addition, the initialization routine PDAF_init is called
! such that the internal initialization of PDAF is performed.
!
! !REVISION HISTORY:
! 2008-10 - Lars Nerger - Initial code
! Later revisions - see svn log
!
! !USES:
  USE mod_model, &        ! Model variables
       ONLY: step_null, dim_state, dim_state_p
  USE mod_parallel, &     ! Parallelization variables
       ONLY: mype_world, n_modeltasks, task_id, &
       COMM_model, COMM_filter, COMM_couple, filterpe, abort_parallel
  USE mod_assimilation, & ! Variables for assimilation
       ONLY: screen, filtertype, subtype, dim_ens, delt_obs, &
       rms_obs, incremental, covartype, type_forget, forget, &
       epsilon, rank_analysis_enkf, locweight, local_range, srange, &
       int_rediag, filename, type_trans, dim_obs, type_sqrt, &
       dim_lag, file_syntobs, twin_experiment, observe_ens, &
       pf_res_type, pf_noise_type, pf_noise_amp

  IMPLICIT NONE

! !CALLING SEQUENCE:
! Called by: main
! Calls: init_pdaf_parse
! Calls: init_pdaf_info
! Calls: PDAF_init
!EOP

! Local variables
  INTEGER :: filter_param_i(7) ! Integer parameter array for filter
  REAL    :: filter_param_r(2) ! Real parameter array for filter
  integer :: status_pdaf       ! PDAF status flag

  ! External subroutines
  EXTERNAL :: init_seik_pdaf  ! SEIK ensemble initialization
  EXTERNAL :: init_seek_pdaf  ! SEEK EOF initialization
  EXTERNAL :: init_enkf_pdaf  ! EnKF ensemble initialization
  

! ***************************
! ***   Initialize PDAF   ***
! ***************************

  IF (mype_world == 0) THEN
     WRITE (*,'(/1x,a)') 'INITIALIZE PDAF'
  END IF


! **********************************************************
! ***   CONTROL OF PDAF - used in call to PDAF_init      ***
! **********************************************************

! *** IO options ***
  screen      = 2   ! Write screen output (1) for output, (2) add timings

! *** Filter specific variables
  filtertype = 1    ! Type of filter
                    !   (0) SEEK
                    !   (1) SEIK
                    !   (2) EnKF
                    !   (3) LSEIK
                    !   (4) ETKF
                    !   (5) LETKF
                    !   (6) ESTKF
                    !   (7) LESTKF
                    !   (8) localized EnKF
                    !   (9) NETF
                    !  (10) LNETF
                    !  (11) GENOBS: Generate synthetic observations
                    !  (12) PF
  dim_ens = 280     ! Size of ensemble for all ensemble filters
                    ! Number of EOFs to be used for SEEK
  dim_lag = 0       ! Size of lag in smoother
  subtype = 0       ! subtype of filter: 
                    !   SEEK: 
                    !     (0) evolve normalized modes
                    !     (1) evolve scaled modes with unit U
                    !     (2) fixed basis (V); variable U matrix
                    !     (3) fixed covar matrix (V,U kept static)
                    !   SEIK:
                    !     (0) mean forecast; new formulation
                    !     (1) mean forecast; old formulation
                    !     (2) fixed error space basis
                    !     (3) fixed state covariance matrix
                    !     (4) SEIK with ensemble transformation
                    !   EnKF:
                    !     (0) analysis for large observation dimension
                    !     (1) analysis for small observation dimension
                    !   LSEIK:
                    !     (0) mean forecast;
                    !     (2) fixed error space basis
                    !     (3) fixed state covariance matrix
                    !     (4) LSEIK with ensemble transformation
                    !   ETKF:
                    !     (0) ETKF using T-matrix like SEIK
                    !     (1) ETKF following Hunt et al. (2007)
                    !       There are no fixed basis/covariance cases, as
                    !       these are equivalent to SEIK subtypes 2/3
                    !   LETKF:
                    !     (0) LETKF using T-matrix like SEIK
                    !     (1) LETKF following Hunt et al. (2007)
                    !       There are no fixed basis/covariance cases, as
                    !       these are equivalent to LSEIK subtypes 2/3
                    !   ESTKF:
                    !     (0) Standard form of ESTKF
                    !     (2) fixed ensemble perturbations
                    !     (3) fixed state covariance matrix
                    !   LESTKF:
                    !     (0) Standard form of LESTKF
                    !     (2) fixed ensemble perturbations
                    !     (3) fixed state covariance matrix
                    !   LEnKF:
                    !     (0) Standard form of EnKF with covariance localization
                    !   NETF:
                    !     (0) Standard form of NETF
                    !   LNETF:
                    !     (0) Standard form of LNETF
                    !   PF:
                    !     (0) Standard form of PF
  type_trans = 0    ! Type of ensemble transformation
                    !   SEIK/LSEIK and ESTKF/LESTKF:
                    !     (0) use deterministic omega
                    !     (1) use random orthonormal omega orthogonal to (1,...,1)^T
                    !     (2) use product of (0) with random orthonormal matrix with
                    !         eigenvector (1,...,1)^T
                    !   ETKF/LETKF:
                    !     (0) use deterministic symmetric transformation
                    !     (2) use product of (0) with random orthonormal matrix with
                    !         eigenvector (1,...,1)^T
                    !   NETF/LNETF:
                    !     (0) use random orthonormal transformation orthogonal to (1,...,1)^T
                    !     (1) use identity transformation
  type_forget = 0   ! Type of forgetting factor in SEIK/LSEIK/ETKF/LETKF/ESTKF/LESTKF
                    !   (0) fixed
                    !   (1) global adaptive
                    !   (2) local adaptive for LSEIK/LETKF/LESTKF
  forget  = 1.0     ! Fixed forgetting factor
  type_sqrt = 0     ! Type of transform matrix square-root
                    !   (0) symmetric square root, (1) Cholesky decomposition
  observe_ens = 0   ! How to apply H when computing residual in ESTKF/ETKF/SEIK
                    !   (0) apply H to ensemble mean, (1) apply H to all ensemble states then average
                    !   Choice (1) should be used when applying a onlinear observation operator
  incremental = 0   ! (1) to perform incremental updating (only in SEIK/LSEIK!)
  covartype = 1     ! Definition of factor in covar. matrix used in SEIK
                    !   (0) for dim_ens^-1 (old SEIK)
                    !   (1) for (dim_ens-1)^-1 (real ensemble covariance matrix)
                    !   This parameter has also to be set internally in PDAF_init.
  rank_analysis_enkf = 0   ! rank to be considered for inversion of HPH
                    ! in analysis of EnKF; (0) for analysis w/o eigendecomposition
  int_rediag = 1    ! Interval of analysis steps to perform 
                    !    re-diagonalization in SEEK
  epsilon = 1.0E-4  ! epsilon for approx. TLM evolution in SEEK
  pf_res_type = 1   ! Resampling type for particle filter
                    !   (1) probabilistic resampling
                    !   (2) stochastic universal resampling
                    !   (3) residual resampling
  pf_noise_type = 0 ! Type of pertubing noise in PF: (0) no perturbations
                    ! (1) constant stddev, (2) amplitude of stddev relative of ensemble variance
  pf_noise_amp = 0.0 ! Noise amplitude for particle filter


! *********************************************************************
! ***   Settings for analysis steps  - used in call-back routines   ***
! *********************************************************************

! *** Whether to run twin experimnet assimilating synthetic observations ***
  twin_experiment = .false.

! *** Forecast length (time interval between analysis steps) ***
  delt_obs = 2     ! Number of time steps between analysis/assimilation steps

! *** specifications for observations ***
  ! avg. observation error (used for assimilation)
  rms_obs = 1.0     ! This error is the standard deviation 
                    ! for the Gaussian distribution 
  dim_obs = dim_state  ! All grid points are observed

! *** Localization settings
  locweight = 0     ! Type of localizating weighting
                    ! For LESTKF, LETKF, and LSEIK
                    !   (0) constant weight of 1
                    !   (1) exponentially decreasing with SRANGE for observed ensemble
                    !   (2) sqrt of 5th-order polynomial for observed ensemble
                    !   (3) exponentially decreasing with SRANGE for obs. error matrix
                    !   (4) 5th-order polynomial for obs. error matrix
                    !   (5) 5th-order polynomial for observed ensemble
                    !   (6) regulated localization of R with mean error variance
                    !   (7) regulated localization of R with single-point error variance
                    ! For LEnKF
                    !   (0) constant weight of 1
                    !   (1) exponentially decreasing with SRANGE
                    !   (2) 5th-order polynomial weight function
  local_range = 10  ! Range in grid points for observation domain in LSEIK/LETKF
  srange = local_range  ! Support range for 5th-order polynomial
                    ! or range for 1/e for exponential weighting

! *** File names
  filename = 'output.dat'       ! Name of output file
  file_syntobs = 'syntobs.nc'   ! File holding synthetic observations generated by PDAF


! ***********************************
! *** Some optional functionality ***
! ***********************************

! *** Parse command line options   ***
! *** This is optional, but useful ***

  call init_pdaf_parse()


! *** Initial Screen output ***
! *** This is optional      ***

  IF (mype_world == 0) call init_pdaf_info()


! *****************************************************
! *** Call PDAF initialization routine on all PEs.  ***
! ***                                               ***
! *** Here, the full selection of filters is        ***
! *** implemented. In a real implementation, one    ***
! *** reduces this to selected filters.             ***
! ***                                               ***
! *** For all filters, first the arrays of integer  ***
! *** and real number parameters are initialized.   ***
! *** Subsequently, PDAF_init is called.            ***
! *****************************************************

  whichinit: IF (filtertype == 0) THEN
     ! *** SEEK ***
     filter_param_i(1) = dim_state_p ! State dimension
     filter_param_i(2) = dim_ens     ! Number of EOFs
     filter_param_r(1) = forget      ! Forgetting factor
     filter_param_r(2) = epsilon     ! Epsilon for tangent linear forecast
! Optional parameters; you need to re-set the number of parameters if you use them
!      filter_param_i(3) = int_rediag  ! Interval to perform rediagonalization
!      filter_param_i(4) = incremental ! Whether to perform incremental analysis

     CALL PDAF_init(filtertype, subtype, step_null, &
          filter_param_i, 2, &
          filter_param_r, 2, &
          COMM_model, COMM_filter, COMM_couple, &
          task_id, n_modeltasks, filterpe, init_seek_pdaf, &
          screen, status_pdaf)
  ELSEIF (filtertype == 2) THEN
     ! *** EnKF ***
     filter_param_i(1) = dim_state_p ! State dimension
     filter_param_i(2) = dim_ens     ! Size of ensemble
     filter_param_r(1) = forget      ! Forgetting factor
! Optional parameters; you need to re-set the number of parameters if you use them
      filter_param_i(3) = rank_analysis_enkf ! Rank of pseudo-inverse in analysis
      filter_param_i(4) = incremental ! Whether to perform incremental analysis
      filter_param_i(5) = dim_lag    ! Whether to perform incremental analysis

     CALL PDAF_init(filtertype, subtype, step_null, &
          filter_param_i, 5, &
          filter_param_r, 2, &
          COMM_model, COMM_filter, COMM_couple, &
          task_id, n_modeltasks, filterpe, init_enkf_pdaf, &
          screen, status_pdaf)
  ELSEIF (filtertype == 12) THEN
     ! *** Particle Filter ***
     filter_param_i(1) = dim_state_p   ! State dimension
     filter_param_i(2) = dim_ens       ! Size of ensemble
     filter_param_r(1) = pf_noise_amp  ! Noise amplitude
! Optional parameters; you need to re-set the number of parameters if you use them
     filter_param_i(3) = pf_res_type   ! Resampling type
     filter_param_i(4) = pf_noise_type ! Perturbation type

     CALL PDAF_init(filtertype, subtype, step_null, &
          filter_param_i, 4, &
          filter_param_r, 1, &
          COMM_model, COMM_filter, COMM_couple, &
          task_id, n_modeltasks, filterpe, init_enkf_pdaf, &
          screen, status_pdaf)
  ELSE
     ! *** All other filters                                    ***
     ! *** SEIK, LSEIK, ETKF, LETKF, ESTKF, LESTKF, NETF, LNETF ***
     ! *** and generation of synthetic observations (GENOBS)    ***
     filter_param_i(1) = dim_state_p ! State dimension
     filter_param_i(2) = dim_ens     ! Size of ensemble
     filter_param_r(1) = forget      ! Forgetting factor
! Optional parameters; you need to re-set the number of parameters if you use them
     filter_param_i(3) = dim_lag     ! Size of lag in smoother
!      filter_param_i(4) = incremental ! Whether to perform incremental analysis
!      filter_param_i(5) = type_forget ! Type of forgetting factor
!      filter_param_i(6) = type_trans  ! Type of ensemble transformation
!      filter_param_i(7) = type_sqrt   ! Type of transform square-root (SEIK-sub4/ESTKF)
!      filter_param_i(8) = observe_ens ! Apply H to ensemble or ensmeble mean for residual (ESTKF/ETKF/SEIK)

     CALL PDAF_init(filtertype, subtype, step_null, &
          filter_param_i, 3, &
          filter_param_r, 2, &
          COMM_model, COMM_filter, COMM_couple, &
          task_id, n_modeltasks, filterpe, init_seik_pdaf, &
          screen, status_pdaf)
  END IF whichinit

! *** Check whether initialization of PDAF was successful ***
  IF (status_pdaf /= 0) THEN
     WRITE (*,'(/1x,a6,i3,a43,i4,a1/)') &
          'ERROR ', status_pdaf, &
          ' in initialization of PDAF - stopping! (PE ', mype_world,')'
     CALL abort_parallel()
  END IF

! *** Initialize file for synthetic observations
  IF (filtertype==11 .and. mype_world==0) THEN
     CALL init_file_syn_obs(dim_state, file_syntobs, 1)
  END IF

END SUBROUTINE init_pdaf
