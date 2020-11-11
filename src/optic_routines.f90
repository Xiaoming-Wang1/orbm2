!
! Copyright (C) 2001-2007 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!

!-----------------------------------------------------------------------
SUBROUTINE optic_readin()
  !-----------------------------------------------------------------------
  !
  ! ... Read in the gipaw input file. The input file consists of a
  ! ... single namelist &inputgipaw. See doc/user-manual.pdf for the
  ! ... list of input keywords.
  !
  USE optic_module
  USE io_files,         ONLY : prefix, tmp_dir  
  USE io_global,        ONLY : ionode
  USE us,               ONLY : spline_ps
  USE mp_images,        ONLY : my_image_id

  ! -- local variables ---------------------------------------------------
  implicit none
  integer :: ios
  character(len=256), external :: trimcheck
  character(len=80) :: diagonalization, verbosity
  namelist /inputoptic/ job, prefix, tmp_dir, conv_threshold, restart_mode, &
                        q_gipaw, iverbosity,  &
                        spline_ps, isolve, max_seconds, verbosity
                        

  if (.not. ionode .or. my_image_id > 0) goto 400
    
  call input_from_file()
    
  ! define input default values
  call get_environment_variable( 'ESPRESSO_TMPDIR', tmp_dir ) 
  if (trim(tmp_dir) == ' ') tmp_dir = './scratch/'
  tmp_dir = trimcheck(tmp_dir)
  job = ''
  prefix = 'pwscf'
  restart_mode = 'restart'
  conv_threshold = 1d-14
  q_gipaw = 0.01d0
  iverbosity = -1
  verbosity = 'low'
  spline_ps = .true.
  isolve = -1
  max_seconds  =  1.d7

  ! read input    
  read( 5, inputoptic, err = 200, iostat = ios )

  ! check input
  if (max_seconds < 0.1d0) call errore ('optic_readin', ' wrong max_seconds', 1)
200 call errore('optic_readin', 'reading inputoptic namelist', abs(ios))

  ! further checks
  if (iverbosity /= -1) &
     call errore('optic_readin', '*** iverbosity is obsolete, use verbosity instead ***', 1)


  select case (verbosity)
     case('low')
       iverbosity = 1
     case('medium')
       iverbosity = 11
     case('high')
       iverbosity = 21
     case default
       call errore('optic_readin', 'verbosity can be ''low'', ''medium'' or ''high''', 1)
  end select
400 continue

#ifdef __MPI
  ! broadcast input variables  
  call optic_bcast_input
#endif

END SUBROUTINE optic_readin


#ifdef __MPI
!-----------------------------------------------------------------------
SUBROUTINE optic_bcast_input
  !-----------------------------------------------------------------------
  !
  ! ... Broadcast input data to all processors 
  !
  USE optic_module
  USE mp_world,      ONLY : world_comm
  USE mp,            ONLY : mp_bcast
  USE io_files,      ONLY : prefix, tmp_dir
  USE us,            ONLY : spline_ps

  implicit none
  integer :: root = 0

  call mp_bcast(job, root, world_comm)
  call mp_bcast(prefix, root, world_comm)
  call mp_bcast(tmp_dir, root, world_comm)
  call mp_bcast(conv_threshold, root, world_comm)
  call mp_bcast(q_gipaw, root, world_comm)
  call mp_bcast(iverbosity, root, world_comm)
  call mp_bcast(spline_ps, root, world_comm)
  call mp_bcast(isolve, root, world_comm)
  call mp_bcast(max_seconds, root, world_comm)
  call mp_bcast(restart_mode, root, world_comm)

END SUBROUTINE optic_bcast_input
#endif
  
!-----------------------------------------------------------------------
SUBROUTINE optic_allocate
  !-----------------------------------------------------------------------
  !
  ! ... Allocate memory for GIPAW
  !
  USE optic_module
  USE ions_base,     ONLY : ntyp => nsp
  USE pwcom
    
  implicit none
  
  ! wavefunction at k+q  
  !allocate(evq(npwx,nbnd))

  ! eigenvalues
  !allocate(etq(nbnd,nkstot))

  ! GIPAW projectors
  !if (.not. allocated(paw_recon)) allocate(paw_recon(ntyp))
    
END SUBROUTINE optic_allocate

!-----------------------------------------------------------------------
SUBROUTINE optic_summary
  !-----------------------------------------------------------------------
  !
  ! ... Print a short summary of the calculation
  !
  USE optic_module
  USE io_global,     ONLY : stdout
  USE cellmd,        ONLY : cell_factor
  USE gvecw,         ONLY : ecutwfc
  USE us,            ONLY : spline_ps
  implicit none

  if (.not. spline_ps) then
      write(stdout,*)
      call infomsg('optic_summary', 'spline_ps is .false., expect some extrapolation errors')
  endif

  write(stdout,*)
  write(stdout,"(5X,'q-space interpolation up to ',F8.2,' Rydberg')") ecutwfc*cell_factor
  write(stdout,*)
  

  write(stdout,*)


  flush(stdout)

END SUBROUTINE optic_summary
  

!-----------------------------------------------------------------------
SUBROUTINE optic_openfil
  !-----------------------------------------------------------------------
  !
  ! ... Open files needed for GIPAW
  !
  USE optic_module
  USE wvfct,            ONLY : nbnd, npwx
  USE io_files,         ONLY : iunwfc, nwordwfc
  USE noncollin_module, ONLY : npol
  USE buffers,          ONLY : open_buffer
  USE control_flags,    ONLY : io_level    
  IMPLICIT NONE  

  logical :: exst

  !
  ! ... nwordwfc is the record length (IN REAL WORDS)
  ! ... for the direct-access file containing wavefunctions
  ! ... io_level > 0 : open a file; io_level <= 0 : open a buffer
  !
  nwordwfc = nbnd*npwx*npol
  CALL open_buffer( iunwfc, 'wfc', nwordwfc, io_level, exst )

END SUBROUTINE optic_openfil


!-----------------------------------------------------------------------
SUBROUTINE optic_closefil
  !-----------------------------------------------------------------------
  !
  ! ... Close files opened by GIPAW, if any
  !
  return

END SUBROUTINE optic_closefil

!-----------------------------------------------------------------------
SUBROUTINE print_clock_optic
  !-----------------------------------------------------------------------
  !
  ! ... Print clocks
  !
  USE io_global,  ONLY : stdout
  IMPLICIT NONE

  write(stdout,*) '    Initialization:'
  call print_clock ('setup')
  write(stdout,*)
  write(stdout,*) '    Linear response'
  call print_clock ('greenf')
  call print_clock ('cgsolve')
  call print_clock ('ch_psi')
  write(stdout,*)
  write(stdout,*) '    Apply operators'
  call print_clock ('h_psi')
  call print_clock ('apply_vel')
  write(stdout,*)
  write(stdout,*) '    General routines'
  call print_clock ('calbec')
  call print_clock ('fft')
  call print_clock ('ffts')
  call print_clock ('fftw')
  call print_clock ('cinterpolate')
  call print_clock ('davcio')
  call print_clock ('write_rec')
  write(stdout,*)

#ifdef __MPI
  write(stdout,*) '    Parallel routines'
  call print_clock ('reduce')  
  call print_clock( 'fft_scatter' )
  call print_clock( 'ALLTOALL' )
  write(stdout,*)
#endif


END SUBROUTINE print_clock_optic


!-----------------------------------------------------------------------
SUBROUTINE optic_memory_report
  !-----------------------------------------------------------------------
  !
  ! ... Print estimated memory usage
  !
  USE io_global,                 ONLY : stdout
  USE noncollin_module,          ONLY : npol
  USE uspp,                      ONLY : okvan, nkb
  USE fft_base,                  ONLY : dffts
  USE pwcom
  IMPLICIT NONE
  integer, parameter :: Mb=1024*1024, complex_size=16, real_size=8

  ! the conversions to double prevent integer overflow in very large run
  write(stdout,'(5x,"Largest allocated arrays",5x,"est. size (Mb)",5x,"dimensions")')

  write(stdout,'(8x,"KS wavefunctions at k     ",f10.2," Mb",5x,"(",i8,",",i5,")")') &
     complex_size*nbnd*npol*DBLE(npwx)/Mb, npwx*npol,nbnd
  write(stdout,'(8x,"KS wavefunctions at k+q   ",f10.2," Mb",5x,"(",i8,",",i5,")")') &
     complex_size*nbnd*npol*DBLE(npwx)/Mb, npwx*npol,nbnd
  write(stdout,'(8x,"First-order wavefunctions ",f10.2," Mb",5x,"(",i8,",",i5,",",i3")")') &
     complex_size*nbnd*npol*DBLE(npwx)*10/Mb, npwx*npol,nbnd,10
  if (okvan) &
  write(stdout,'(8x,"First-order wavefunct (US)",f10.2," Mb",5x,"(",i8,",",i5,",",i3")")') &
     complex_size*nbnd*npol*DBLE(npwx)*6/Mb, npwx*npol,nbnd,6

  write(stdout,'(8x,"Charge/spin density       ",f10.2," Mb",5x,"(",i8,",",i5,")")') &
     real_size*dble(dffts%nnr)*nspin/Mb, dffts%nnr, nspin
  
  write(stdout,'(8x,"NL pseudopotentials       ",f10.2," Mb",5x,"(",i8,",",i5,")")') &
     complex_size*nkb*DBLE(npwx)/Mb, npwx, nkb
  write(stdout,*)

END SUBROUTINE optic_memory_report


