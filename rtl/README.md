all the wave files are named dump.vcd

PACKET --> PACKAGE --> BATCH --> SAMPLE

- PACKET - is defined as the total number of samples that are in one packet that one has to compress and is inputted at once inside the input buffer by the overall machine

- PACKAGE - is defined as the number of batches after which one should give a reference sample 

- BATCH - is defined as the number of samples that are grouped together for k estimation at once

- SAMPLE - is defined as the indiviual 16bit samples that are going to be compressed

The overall architecture is for a rotating ram buffer method to be implemented where there are a couple of modules that are working in tandem, the modules are bit packer, k estimation, encoder from what I want I am working on implementing three ram buffers assuming they are names ramA ramB and ramC the process will involve taking in the input buffer and loading the delta processed inputs into ramA then in the following time step we process ramA with k estimation and load delta processed values into ramB then in the next timestep ramC is loaded with delta processed values and ramB is k estimated and ramA will be encoded into the output buffer again since ramA is basically overwritable after this we can use ramA to again take in the output since it will always be 1st,4th , 7th point we can define the values easily for each package however there is the limitation of using only the difference we can easily assign a parameter to rach of the rams and then dynamically allocate the reference batch as well , thus it is quite easy to pivot to either of the methods and this piplining strategy also simplifies the process of timing

more specifically considering the fact that we have to send the data into multiple different blocks independently a couple things matter 
 - the ram and which stage is it in 
 - the ram itself which ram it is 
 - capturing the number of samples that have already gone through
these three are of utmost importance the first two manage how and where the data goes through the last one is the control knob about how the data goes through this to control this we would need to implement a mux that can pipeline the data as well. I implemented this by making it a seperated ram generator block 

BIT_PACK.v
- clk - wire
		standard clock input
- rst_n - wire
		- standard reset option clears internal shifter_reg and all other internal state registers

- pack_en - wire
			- standard enable switch kept high to pack new bits 
- flush_en - wire
			- standard enable switch kept high to flush out any remaining bits with 0 as padding

- bits - wire array
		- 32 bits that can be inputted at a time by using pack_en wire at a time
- count - wire array
		- 5 bits capturing the number of bits that are useful disregarding any padding as is by masking( that is to say a bit 0x12345678 with count 5'd12 would only capture 0x678 as useful bits and mask out 0x12345 point to be noted is that the bits are to right alligned)

- ram_data - reg
			- output data in case of flush_en kept high or the shifter reg having values greater than 32
- ram_we - reg
			- standard output reg designed to mention that a word(16bit) is being outputted
- packer_ready - reg 
			- standard output value mentioning weather the machine is ready

The mechanism work by combinationally calculating the shifts in the reg to fast track progress however it still requires clockedge specifically positive clock edge to move the signals as a result of this a unique hickup that is present is that one needs to give it an extra clock cycle before flushing the signal in order for it to work on the last stored value honestly it is basically a feature visible everytime an incomplete bit is calculated that is to say when each bit group is being stored it takes one clock cycle for it to clock the value instead of doing it in real time after that flushing the values yeilds a padded value with 0 as padding


DELTA_PROCESSING

- previous_x - wire array
			- value of last array value is the responsibility module to provide this value is not stored internally

- current_x - wire array
			- current value to be modified
- encoded_delta - wire array
				- encoded value that is the output has to taken in at the same time as when previous and current values are provided in a fifo or buffer as the user wishes
The machine uses a simple zigzag golumb encoding where it calculates the delta in 17bit buffer (where the 17th bit is specifically to prevent overflow since we are dealing with 16bit values) then assuming it to be positive and negative at the same time it calculate positive result (2 * delta) and negative result (2 * delta - 1) ( the delta for calculating the negative result is converted to its positive value -1 -> 1 and -3 -> 3) finally based on weather the delta was positive or negative it is assigned to the output value. 
The truly fascinating design choice was to use the combinational circuit here that is to say the first few days I was looking into how to first check weather the value delta is positive or negative however considering that in rtl we will inevitably be making blocks for positive and negative values it would seem wasteful of time not to use a mux to assigning a value and this instead of making a sequential of first calculating weather it is positive or negative and then assigning it through multiple muxes I could now use one mux at the end alone to simply calculate the final value


K_ESTIMATOR

- SAMPLE_SIZE - parameter
				- this is there so as to limit the number of k values that will be calculated 
- clk - wire
		- standard wire to run the block
- rst_n - wire
		- is inverse that is for one session one keeps it high since the moment it loses its high value it will lose all data and clear out all the data registers
- start - wire
		- standard high wire for one session
- block_size - wire
			- value input that is the block size literally input I made it an input value instead of a parameter since the value was supposed to change on a reference block and thus keeping it fixed would have caused error
- start_addr - wire
			- since I am using a rotating ram block thus I need to mention where to start the values 0 means not a reference block and 1 means it is a reference block and thus will leave the first block empty 
- done - wire 
		- standard done indicator
- optimal_k - reg
			- stores the optimal k that was calculated so as to tranfer the value to the encoder block
- min_length - reg
				- debugging register not something required
- mem_addr - reg
			- configured to output a specific value the start address controls the first mem_addr here 
- mem_data - wire
			- input data block when mem_addr outputs a new number it expects a new value in mem_data

The original method was to let the k_estimation decide weather the batch it is processing is the reference batch or simply just another batch however now that I am using a rotating ram based approach I can encode the approach into the overall encoder such that for a particular ram it will always be considered a reference batch since the assuming it is every 4th batch  it will always be ramA  or something like if it is every 5th batch then it is ramB 

RAM
- DATA_WIDTH = 16
				- width of the data being stored
- ADDR_WIDTH = 10
				- address width
- clk- wire
		- standard wire to drive the system
- we - wire
		- write wire that clears all the data and overwrites it with new data
 - addr - wire array
		 - address at which data has to be written
- din - wire array
		- data in for when we want to write the data in 
- dout - wire array
		- wire array for when we want to capture the data we want out

ENCODER

- clk - wire 
		- standard wire to drive the system
- rst_n - wire
		- standard wire to start a session here (that is to say keep it high for one session)
- start - wire
		- start encoding signal 
- done -  wire
		- output wire that signals the completion of a block useful for making a progression signal
- encoder_busy - wire
				- encoder busy signal as it says mentions weather the encoder is working on something or the encoding has been completed
- start_addr - wire array
			- signals the start value of the address that the machine should start requesting values from the rotating rams value would vary from 0 and 1 based on the reference block or not
- block_size - wire array
			- length of the array that has to be encoded values would change from 15 to 16 in case of block size being 16 in other cases that could change
- optimal_k - wire array 
			- part of the k_estimator signal array that singals what is the k to be used
- ram_addr -  wire array
			- ram port that requests data from the ram
- ram_data - wire array
			- ram port that accepts data from the ram
- pack_en - wire
			- starts the bit packer module and readies it for packing
- pack_bits - wire array
			- bits that are supposed to packed
- pack_count - wire array
			- number of bits that are supposed to be packed
- packer_ready - wire
			- signals weather the bits are ready to packed


Overall the machine is supposed to take a data by giving mem_addr and then as soon as the mem data comes in it combinationally calculates quotient and remainder and accordingly calculates unary bits and length along with the appending a 0 at the end of unary bits. Now however there was always a concern of overflow while the Rice encoding always works great when the data points are not varying by much and are almost always equal however what if because of anomalical values a encoded byte exceeded the 32bit limit even when k is a smaller value overall that would cause concern since in one lcock cycle bit_pack can only accept 32 bits at once for this I made an anomaly cycler which stores the remaining anomalical value slowly shifting the overall encoded bytes 32 at a time till they all are out and about this should solve the problem or atleast this seemed to solve the issue during testing however this means that each encoder cycle requires more than a fixed number cycles to complete the encoding that breaks the symmetry and thus during the overall pipeline structure I will have to make toggle switch that makes sure that each ram has completed its own process before proceeding
