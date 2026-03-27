#include <stdint.h>
#include "../Interfaces/uart.h"
#include "../Interfaces/plic.h"

const char pass_msg[6] = "PASS\n\r";
const char fail_msg[6] = "FAIL\n\r";

// Helper function to send a string over UART
void uart_print(const char *msg) {
    for (uint32_t i = 0; i < 6; i++) {
        Buggyv32_Uart_Tx(msg[i]);
    }
}

int main(void) {
    // Initialize UART
    Buggyv32_Uart_Init(UART_BAUD_DIV);
   
    uart_print(pass_msg);
    uart_print(fail_msg);
    
    return 0;
}