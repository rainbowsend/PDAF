!> Module with model-specific variables
!!
!! For the template this module simulate a module that
!! would be provided by the actual model code.
!!
MODULE mod_model

  IMPLICIT NONE
  SAVE

  INTEGER :: step_final=4          ! Final time step
  REAL    :: dt=0.1                ! Time step size

END MODULE mod_model
