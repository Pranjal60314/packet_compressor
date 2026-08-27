import os
import sys
import cmd
import shlex
import argparse
import pathfiles as pf
import helper as hp
import verilog_sim as vs
import pkt_test_indi as pkti
import auto_verify as av


def print_help():
    print("""
Usage: <command> [options]

Commands:
  help                    Show this menu.
  list                    List available testbenches.
  clean                   Remove build artifacts, logs, and waveforms.
  exit, quit              Exit the shell.

  tb <tb.v> [rtl...]      Compile and run simulation.
                          Examples:
                            tb tb_encoder.v
                            tb tb_encoder.v encoder.v ram.v
  show <tb.v>             Open simulation waveform in GTKWave.
                          Example:
                            show tb_encoder.v
  profile [options]       Profile a single telemetry chunk using the C model.
                          Options:
                            --file <name>         Binary telemetry file (required)
                            --offset <int>        Sample starting offset (default: 0)
                            --packet-size <int>   Number of samples (default from config)
                            --batch-size <int>    Batch size for compression
                            --package-size <int>  Package size for anchor frames
                          Examples:
                            profile --file AMT00103_raw.bin
                            profile --file AMT00103_raw.bin --offset 4096 --packet-size 2048
  verify [options]        Run multi-packet rtl simulation and verify against C golden model.
                          Options:
                            --file <name>         Binary dataset (required)
                            --samples <int>       Total samples (default: 10000)
                            --packet-size <int>   Packet size (default: 160)
                            --batch-size <int>    Batch size (default: 16)
                            --package-size <int>  Package size (default: 4)
                          Example:
                            verify --file AMT00103_raw.bin --samples 10000 --packet-size 160
  benchmark               Run C reference model against full dataset.
                          Logs: logs/python_sim_log.txt
                                logs/iteration_profiles.csv
  download                Fetch and parse telemetry datasets.
""")


class CompressorShell(cmd.Cmd):
    prompt = "compressor-sh > "

    def __init__(self):
        super().__init__()
        hp.setup_environment(purge_logs=False)
        self.verify_parser = av.create_verify_parser()
        self.profile_parser = pkti.create_profile_parser()

    # Empty line handler (prevents re-running the last command on empty Enter)
    def emptyline(self):
        pass

    def default(self, line):
        print(f" Unknown command: '{line.split()[0]}'. Type 'help' or '?' to see valid operations.")


    def do_list(self, arg):
        """List available testbenches."""
        tbs = [f for f in os.listdir(pf.TB_DIR)]
        print("\nFound Testbenches in TB folder:")
        for tb in tbs:
            print(f"  - {tb}")
        print("")

    def do_clean(self, arg):
        """Remove build artifacts, logs, and waveforms."""
        print("[+] Purging log files and binary outputs...")
        hp.setup_environment(purge_logs=True)
        if os.path.exists(pf.LOG_DIR):
            for file in os.listdir(pf.LOG_DIR):
                if file.endswith(".vvp") or file.endswith(".vcd"):
                    os.remove(os.path.join(pf.LOG_DIR, file))
        print("[\033[92m+\033[0m] Workspace cleaned cleanly.")

    def do_tb(self, arg):
        """Compile and run simulation. Usage: tb <tb_name.v> [source_files...]"""
        args = shlex.split(arg)
        if len(args) < 1:
            print(" Error: Missing testbench name! Usage: tb <tb_name.v> [source_files...]")
            return

        tb_name = args[0]
        tb_path = os.path.join(pf.TB_DIR, tb_name)

        if not os.path.exists(tb_path):
            print(f" Error: Testbench '{tb_name}' not found in {pf.TB_DIR}")
            return

        if len(args) > 1:
            sources = [os.path.join(pf.RTL_DIR, s) for s in args[1:]]
        else:
            sources = [
                os.path.join(pf.RTL_DIR, f) 
                for f in os.listdir(pf.RTL_DIR) 
                if f.endswith(".v")
            ]

        base_name = tb_name.replace(".v", "")
        output_bin = os.path.join(pf.LOG_DIR, f"{base_name}.vvp")

        print(f"\n [\033[94mPreparing {tb_name}\033[0m] -> Using {len(sources)} source file(s)")
        vs.run_verilog_sim(tb_path, sources, output_bin, tb_name)

    def do_show(self, arg):
        """Open simulation waveform in GTKWave. Usage: show <tb_name.v>"""
        args = shlex.split(arg)
        if len(args) < 1:
            print(" Error: Specify which testbench wave to open! Usage: show <tb_name.v>")
            return
        
        tb_name = args[0].replace(".v", "")
        target_vcd = os.path.join(pf.LOG_DIR, f"{tb_name}_dump.vcd")
        vs.show_gtk(target_vcd)

    def do_profile(self, arg):
        """Profile a single telemetry chunk using the C model."""
        args = shlex.split(arg)
        try:
            parsed_args = self.profile_parser.parse_args(args)
        except SystemExit:
            print(" Usage: profile --file <filename> [--offset 0] [--packet-size N] [--batch-size N] [--package-size N]")
            return

        profile_script = os.path.join(pf.BUILD_DIR, "makefile_configs/pkt_test_indi.py")
        cmd = [sys.executable, profile_script, "--file", parsed_args.file, "--offset", str(parsed_args.offset)]

        if parsed_args.packet_size:
            cmd.extend(["--packet-size", str(parsed_args.packet_size)])
        if parsed_args.batch_size:
            cmd.extend(["--batch-size", str(parsed_args.batch_size)])
        if parsed_args.package_size:
            cmd.extend(["--package-size", str(parsed_args.package_size)])

        hp.run_stage("SINGLE CHUNK PROFILING", cmd, "python")

    def do_verify(self, arg):
        """Run multi-packet rtl simulation and verify against C golden model."""
        args = shlex.split(arg)
        try:
            parsed_args = self.verify_parser.parse_args(args)
        except SystemExit:
            print(" Usage: verify --file <filename.bin> [--samples 10000] [--packet-size 160] [--batch-size 16] [--package-size 4]")
            return

        av.run_verification_pipeline(
            dataset_name=parsed_args.file,
            total_samples=parsed_args.samples,
            packet_size=parsed_args.packet_size,
            batch_size=parsed_args.batch_size,
            package_size=parsed_args.package_size
        )

    def do_benchmark(self, arg):
        """Run C reference model against full dataset."""
        compile_cmd = [sys.executable, os.path.join(pf.BUILD_DIR, "makefile_configs/pkt_test.py")]
        hp.run_stage("BENCHMARK", compile_cmd, "python")

    def do_download(self, arg):
        """Fetch and parse telemetry datasets."""
        compile_cmd = [sys.executable, os.path.join(pf.BUILD_DIR, "makefile_configs/kagg.py")]
        hp.run_stage("Downloading datasets", compile_cmd, "python")
        compile_cmd = [sys.executable, os.path.join(pf.BUILD_DIR, "makefile_configs/parser.py")]
        hp.run_stage("Parsing datasets", compile_cmd, "python")

    def do_help(self, arg):
        """Show this help menu."""
        print_help()

    def do_clear(self, arg):
        """Clear the terminal screen."""
        os.system('cls' if os.name == 'nt' else 'clear')

    def do_exit(self, arg):
        """Exit the shell."""
        print("Goodbye!")
        return True

    def do_quit(self, arg):
        """Exit the shell."""
        return self.do_exit(arg)


if __name__ == "__main__":
    print_help()
    print("\n[+] Launching interactive shell...")
    try:
        CompressorShell().cmdloop()
    except (KeyboardInterrupt, EOFError):
        print("\nExiting shell...")