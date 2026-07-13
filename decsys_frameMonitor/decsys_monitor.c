//###########################################################################
//
// FILE:   decsys_frameMonitor.c
// TITLE:  Simple SDLC raw bit logger on F28379D. Using DPLL. Data Line Driven
// AUTHOR: Jayanth Krish
//###########################################################################


#include "F28x_Project.h"


#pragma DATA_SECTION(data_buf, "MYBUF");


#define BLINKY_LED_GPIO 31
#define SDLC_DATA_GPIO  123 //18
#define SDLC_DPLL_GPIO 61  //19
#define DEBUG_GPIO      122 //17


#define PKT_SYNC1       0xAA
#define PKT_SYNC2       0x55
#define PKT_TYPE_SNIFF  0x01    // Tx: 0x01 Rx: 0x02


#define BUF_LEN 5120



volatile Uint16 sample_seen = 0;


volatile Uint16 data_buf[BUF_LEN];
volatile Uint16 snapshot[BUF_LEN];


volatile Uint16 data_count = 0;
volatile Uint16 snapshot_len = 0;



volatile Uint16 block_ready = 0;
volatile Uint16 capture_done = 0;
volatile Uint16 packet_sent = 0;
volatile Uint16 sniff_active = 0;




volatile Uint16 bit_count = 0;
volatile Uint16 work_byte = 0;



__interrupt void xint1_isr(void);
__interrupt void xint2_isr(void);


void scia_init(void);
void scia_xmit(Uint16 a);
void send_packet(Uint16 type, Uint16 part, const volatile Uint16 *buf, Uint16 len);


void clear_capture_buffer(void);


void main(void)
{
    Uint16 part = 1;
    Uint16 len = 0;
    Uint16 i;


    InitSysCtrl();
    InitGpio();


    // LED
    GPIO_SetupPinMux(BLINKY_LED_GPIO, GPIO_MUX_CPU1, 0);
    GPIO_SetupPinOptions(BLINKY_LED_GPIO, GPIO_OUTPUT, GPIO_PUSHPULL);
    GPIO_WritePin(BLINKY_LED_GPIO, 1);   // OFF initially


    // SDLC input pin
    GPIO_SetupPinMux(SDLC_DATA_GPIO, GPIO_MUX_CPU1, 0);
    GPIO_SetupPinOptions(SDLC_DATA_GPIO, GPIO_INPUT, GPIO_ASYNC);


    // DPLL
    GPIO_SetupPinMux(SDLC_DPLL_GPIO, GPIO_MUX_CPU1, 0);
    GPIO_SetupPinOptions(SDLC_DPLL_GPIO, GPIO_INPUT, GPIO_ASYNC);
    
    // Debug
    GPIO_SetupPinMux(DEBUG_GPIO, GPIO_MUX_CPU1, 0);
    GPIO_SetupPinOptions(DEBUG_GPIO, GPIO_OUTPUT, GPIO_PUSHPULL);
    GPIO_WritePin(DEBUG_GPIO, 0);


    // USB-UART LINES
    GPIO_SetupPinMux(43, GPIO_MUX_CPU1, 15);
    GPIO_SetupPinOptions(43, GPIO_INPUT, GPIO_ASYNC);


    GPIO_SetupPinMux(42, GPIO_MUX_CPU1, 15);
    GPIO_SetupPinOptions(42, GPIO_OUTPUT, GPIO_PUSHPULL);


    DINT;
    InitPieCtrl();
    IER = 0x0000;
    IFR = 0x0000;
    InitPieVectTable();


    EALLOW;
    PieVectTable.XINT1_INT  = &xint1_isr; //DPLL
    PieVectTable.XINT2_INT = &xint2_isr;  // data-line edge
    EDIS;


    // DPLL on GPIO123 to XINT1
    GPIO_SetupXINT1Gpio(SDLC_DPLL_GPIO);
    XintRegs.XINT1CR.bit.POLARITY = 1;   // 0: falling edge 1:rising edge
    XintRegs.XINT1CR.bit.ENABLE   = 1;


    // data line on XINT2, trigger on falling edge (idle->active)
    GPIO_SetupXINT2Gpio(SDLC_DATA_GPIO);
    XintRegs.XINT2CR.bit.POLARITY = 0; // falling
    XintRegs.XINT2CR.bit.ENABLE   = 1;



    PieCtrlRegs.PIECTRL.bit.ENPIE = 1;
    PieCtrlRegs.PIEIER1.bit.INTx4 = 1;   // XINT1
    PieCtrlRegs.PIEIER1.bit.INTx5 = 1;   // XINT2
    IER |= M_INT1;


    EINT;
    ERTM;


    // Initialize SCI USB-UART Interface
    scia_init();


    clear_capture_buffer();


    for(;;)
    {
        if(sample_seen)
        {
            //DEBUG
            
            GPIO_WritePin(BLINKY_LED_GPIO, 0);
            GPIO_WritePin(BLINKY_LED_GPIO, 1);


            GPIO_WritePin(DEBUG_GPIO, 1);
            DELAY_US(10);
            GPIO_WritePin(DEBUG_GPIO, 0);
            
            sample_seen = 0;
        }


        if(block_ready)
        {
            DINT;
            len = snapshot_len;
            for(i = 0; i < len; i++)
            {
                snapshot[i] = data_buf[i] & 0x00FF;
            }
            block_ready = 0;
            EINT;


            if(len > 0)
            {
                send_packet(PKT_TYPE_SNIFF, part, snapshot, len);
                packet_sent = 1;
            }
        }
    }
}


__interrupt void xint1_isr(void)
{
    Uint16 level;
    Uint16 bit;


    if(!sniff_active || capture_done)
    {
        PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
        return;
    }

    DELAY_US(10);

    level = GPIO_ReadPin(SDLC_DATA_GPIO);
    bit   = (level != 0U) ? 1U : 0U;

    sample_seen = 1;

    work_byte = (work_byte << 1) | bit;
    bit_count++;


    if(bit_count == 8)
    {
        if(data_count < BUF_LEN)
        {
            data_buf[data_count] = work_byte & 0x00FF;
            data_count++;
        }


        work_byte = 0;
        bit_count = 0;


        if(data_count >= BUF_LEN)
        {
            capture_done = 1;
            snapshot_len = BUF_LEN;
            block_ready = 1;
            sniff_active = 0;
        }
    }



    PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
}


__interrupt void xint2_isr(void)   // SDLC data edge (idle->active)
{
    if(!sniff_active && !capture_done)
    {
        sniff_active     = 1;
        work_byte        = 0;
        bit_count        = 0;
        data_count       = 0;
        block_ready      = 0;
        snapshot_len     = 0;
    }


    PieCtrlRegs.PIEACK.all = PIEACK_GROUP1;
}


void scia_init(void)
{
    // 1 stop bit, no parity, 8-bit character, async, idle-line
    SciaRegs.SCICCR.all = 0x0007;


    // enable TX, RX, internal SCI clock
    SciaRegs.SCICTL1.all = 0x0003;


    // no SCI interrupts needed
    SciaRegs.SCICTL2.all = 0x0000;


    // These baud values are from TI F2837xD SCI echoback-style examples
    SciaRegs.SCIHBAUD.all = 0x0002;
    SciaRegs.SCILBAUD.all = 0x008B;


    // optional FIFO init
    SciaRegs.SCIFFTX.all = 0xE040;
    SciaRegs.SCIFFRX.all = 0x2044;
    SciaRegs.SCIFFCT.all = 0x0000;


    // release SCI from reset
    SciaRegs.SCICTL1.all = 0x0023;
}


void scia_xmit(Uint16 a)
{
    while(SciaRegs.SCIFFTX.bit.TXFFST != 0)
    {
    }


    SciaRegs.SCITXBUF.all = (a & 0x00FF);
}


void send_packet(Uint16 type, Uint16 part, const volatile Uint16 *buf, Uint16 len)
{
    Uint16 i;


    scia_xmit(PKT_SYNC1);
    scia_xmit(PKT_SYNC2);
    scia_xmit(type);
    scia_xmit((part >> 8) & 0x00FF);
    scia_xmit(part & 0x00FF);
    scia_xmit((len >> 8) & 0x00FF);
    scia_xmit(len & 0x00FF);


    for(i = 0; i < len; i++)
    {
        scia_xmit(buf[i] & 0x00FF);
    }
}


void clear_capture_buffer(void)
{
    Uint16 i;


    bit_count = 0;
    work_byte = 0;
    data_count = 0;
    block_ready = 0;
    snapshot_len = 0;


    for(i = 0; i < BUF_LEN; i++)
    {
        data_buf[i] = 0;
    }
}
