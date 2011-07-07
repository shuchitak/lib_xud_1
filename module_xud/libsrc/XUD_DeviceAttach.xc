
#include <xs1.h>
#include <print.h>

#include "XUD_UIFM_Functions.h"
#include "XUD_UIFM_Defines.h"
#include "XUD_USB_Defines.h"
#include "XUD_Support.h"

extern out port reg_write_port;
extern in  port reg_read_port;
extern in  port flag0_port;
extern in  port flag1_port;
extern in  port flag2_port;
extern out port p_usb_txd;

/* States for state machine */
#define STATE_START 0
#define STATE_DETECTK 1
#define STATE_INC_K 2
#define STATE_DETECTJ 3
#define STATE_INC_J 4
#define STATE_VALID 5
#define STATE_INVALID 6
#define STATE_FILT_CHECK_K 7
#define STATE_FILT_CHECK_J 8

#define TUCHEND_DELAY_us  1500 // 1.5ms
#define TUCHEND_DELAY            (TUCHEND_DELAY_us * XCORE_FREQ_MHz / (REF_CLK_DIVIDER+1))
#define INVALID_DELAY_us  2500 // 2.5ms
#define INVALID_DELAY            (INVALID_DELAY_us * XCORE_FREQ_MHz / (REF_CLK_DIVIDER+1))

unsigned chirptime = TUCHEND_DELAY;

extern int resetCount;

/* Assumptions:
 * - In full speed mode
 * - No flags sticky */
int XUD_DeviceAttachHS()
{
    unsigned tmp;
    timer t;
    unsigned time1, time2;
    int chirpCount = 0;
    unsigned state = STATE_START, nextState;
    int loop = 1;
    int complete = 1;
  

    clearbuf(p_usb_txd);
    clearbuf(reg_write_port);
    // On detecting the SE0:
    // De-assert XCVRSelect and set opmode=2
    // DEBUG - write to ulpi reg 0x54. This is:
    // opmode = 0b10, termsel = 1, xcvrsel = 0b00;

    XUD_UIFM_RegWrite(reg_write_port, UIFM_REG_PHYCON, 0x15);
    
    XUD_Sup_Delay(50);

    // DEBUG: This sets IFM mode to DecodeLineState
    // Bit 5 of the CtRL reg (DONTUSE) has a serious effect on
    // driving the k-chirp, regardless of if we actually want to yet or not.
    //XUD_UIFM_RegWrite(reg_write_port, UIFM_REG_CTRL, 0x4);
        

    // Should out a K chirp - Signal HS device to host
    //XUD_Sup_Outpw8(p_usb_txd, 0);
   // p_usb_txd <: 0;

    // Wait for TUCHEND - TUCH
    //XUD_Sup_Delay(chirptime);

   for (int i = 0; i < 25000; i++)
        p_usb_txd <: 0;

   // XUD_Sup_Delay(30000);

    // Clear port buffers to remove k chirp
    clearbuf(p_usb_txd);

    //XUD_UIFM_RegWrite(reg_write_port, UIFM_REG_CTRL, 0x04);
    // J, K, SE0 on flag ports 0, 1, 2 respectively
    // Wait for fs chirp k (i.e. HS chirp j)
    //flag0_port when pinseq(0) :> tmp; // Wait for out k to go




    while(loop)
    {
        switch(state)
        {
            case STATE_START:
                t :> time1;
                chirpCount = 0;
                nextState = STATE_DETECTK;
                break;

            case STATE_DETECTK:
                t :> time2;

                if (time2 - time1 > INVALID_DELAY)
                    nextState = STATE_INVALID;

                flag1_port :> tmp;
                if (tmp)
                    nextState = STATE_FILT_CHECK_K;
                break;

      case STATE_FILT_CHECK_K:
        XUD_Sup_Delay(T_FILT);
        flag1_port :> tmp;
        if (tmp) {
          XUD_Sup_Delay(T_FILT);
          nextState = STATE_INC_K;
        } else {
          nextState = STATE_DETECTK;
        }
        break;

      case STATE_INC_K:
        flag2_port :> tmp;  // check for se0
        if(tmp) {
#ifdef XUD_STATE_LOGGING
          addDeviceState(STATE_K_INVALID);
#endif
          nextState = STATE_INVALID;
        } else {
#ifdef XUD_STATE_LOGGING
          addDeviceState(STATE_K_VALID);
#endif
          chirpCount++;
          if (chirpCount == 6) {
            nextState = STATE_VALID;
          } else {
            nextState = STATE_DETECTJ;
          }
        }
        break;

      case STATE_DETECTJ:
        t :> time2;

        if (time2 - time1 > INVALID_DELAY)
          nextState = STATE_INVALID;

        flag0_port :> tmp;
        if (tmp)
          nextState = STATE_FILT_CHECK_J;
        break;

      case STATE_FILT_CHECK_J:
        XUD_Sup_Delay(T_FILT);
        flag0_port :> tmp;
        if (tmp) {
            XUD_Sup_Delay(T_FILT);
            nextState = STATE_INC_J;
        } else {
            nextState = STATE_DETECTJ;
        }
        break;

      case STATE_INC_J:
        flag2_port :> tmp;  // check for se0
        if(tmp) {
#ifdef XUD_STATE_LOGGING
          addDeviceState(STATE_J_INVALID);
#endif
          nextState = STATE_INVALID;
        } else {
#ifdef XUD_STATE_LOGGING
          addDeviceState(STATE_J_VALID);
#endif
          chirpCount++;
          if (chirpCount == 6) {
            nextState = STATE_VALID;
          } else {
            nextState = STATE_DETECTK;
          }
        }
        break;

      case STATE_INVALID:
        loop = 0;
        complete = 0;
        //return 0;
        //nextState = STATE_START;
        break;

      case STATE_VALID:
        //printstr("good chirp");
        loop = 0;
        break;
    }

    state = nextState;
  }

  if (complete) {

    // Three pairs of KJ received... de-assert TermSelect... (and opmode = 0, suspendm = 1)
    XUD_UIFM_RegWrite(reg_write_port, UIFM_REG_PHYCON, 0x1);

    //wait for SE0 (TODO consume other chirps?)
    flag2_port when pinseq(1) :> tmp;

  }
    //wait for SE0 end
    flag2_port when pinseq(0) :> tmp;

  return complete;
}

