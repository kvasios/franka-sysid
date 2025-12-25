# franka-sysid

System identification stack for the Franka robot, derived from the upstream
`robot_payload_id` component of *Scalable Real2Sim: Physics-Aware Asset
Generation Via Robotic Pick-and-Place Setups*.

## Attribution / Upstream

- Upstream repository: `https://github.com/nepfaff/scalable-real2sim`
- The upstream system identification component was named `robot_payload_id`.
  In this repository, it lives in `franka_sysid/` (Python-importable module
  name). The repository itself is named `franka-sysid`.

## License

This repository is distributed under the MIT license (see `LICENSE`), **except
where a file or notice indicates otherwise**. See `NOTICE` for third-party
attributions and additional licenses embedded in individual files.

---

## Installation

This repo uses Poetry for dependency management.

### Ubuntu 24.04 / Python version note

Ubuntu 24.04 ships Python 3.12 by default, but this project currently targets **Python
3.10** (see `pyproject.toml`). The easiest way to get a consistent Python version on
Ubuntu 24.04 is to use **micromamba**.

### Recommended: micromamba env + Poetry (Poetry installs into the active env)

Create and activate a Python 3.10 env:

```bash
micromamba create -y -f environment.yml
micromamba activate franka-sysid
```

Configure Poetry to use the **currently active** environment (instead of creating its
own virtualenv):

```bash
poetry config virtualenvs.create false --local
```

Next, install all the required dependencies to the virtual environment with the
following command:

```bash
poetry install -vvv
```

(the `-vvv` flag adds verbose output).

If you still need the legacy IIWA / KUKA hardware-station glue, install `iiwa_setup`
manually:

```bash
pip install 'iiwa-setup @ git+https://github.com/nepfaff/iiwa_setup.git'
```

If you use **local/source** Drake and/or manipulation checkouts (instead of pip wheels),
make sure they are on your `PYTHONPATH` after activating your environment (micromamba or
otherwise), e.g.:

```bash
export PYTHONPATH=~/drake-build/install/lib/python3.10/site-packages:${PYTHONPATH}
export PYTHONPATH=~/manipulation:${PYTHONPATH}
```

If `poetry install` complains that `poetry.lock` is stale, regenerate it with:

```bash
poetry lock
```

Install `git-lfs` (if required by your data/assets):

```bash
git-lfs install
git-lfs pull
```

## Optimal Experiment Design

```bash
python3 scripts/design_optimal_excitation_trajectories.py \
  --optimizer "black_box" --cost_function "condition_number_and_e_optimality" \
  --num_fourier_terms 5 --num_timesteps 1000 --use_one_link_arm --logging_path logs/traj
```

*Hint:* Run on multiple cores using `--num_workers`. When using multiple workers,
using `--log_level ERROR` is needed for nice progress bars.

*Note:* It is recommended to design trajectories without considering reflected inertia
and joint friction as this seems to lead to better results, even when identifying these
parameters later on.

The `--payload_only` flag enables designing trajectories that only optimize the
excitation of the payload parameters. These are the 10 inertial parameters of the last
link.

We found the following to be decent parameters:

```bash
python3 scripts/design_optimal_excitation_trajectories.py --optimizer black_box \
  --cost_function condition_number_and_e_optimality --nevergrad_method NGOpt \
  --num_fourier_terms 5 --max_al_iterations 20 --budget 100000 --mu_initial 5 \
  --min_time_horizon 10 --max_time_horizon 10 --num_timesteps 1000 --num_workers 32 \
  --mu_multiplier 1.5 --omega 0.6283 --log_level ERROR --initial_guess_scaling 0.1 \
  --logging_path logs/gripper_payload_box/iiwa_eoptimality_10s_5Fterm_1000timesteps_20_100000
```

We achieved a condition number of `116.7`, a e-optimality of `-2883`, equality
constraint violations of `1e-5`, and inequality constraint violations of `1e-6`. Note
that in practice, the condition number of real-world data obtained with this trajectory
is much lower.

It is recommended to pick the biggest value of `--initial_guess_scaling` that results in
an initial guess without collisions.

### Use a Fourier series trajectory as an initial guess for BSpline trajectory optimization

First, convert the optimized Fourier series trajectory into a BSpline trajectory:

```bash
python3 scripts/create_bspline_traj_from_fourier_series.py \
  --traj_parameter_path logs/fourier_series_traj \
  --save_dir logs/converted_trajs/bspline_traj \
  --num_control_points_initial 30 --num_timesteps 1000
```

Second, use the converted trajectory as the initial guess:

```bash
python3 scripts/design_optimal_excitation_trajectories.py \
  --optimizer "black_box" --cost_function "condition_number_and_e_optimality" \
  --num_timesteps 1000 --use_one_link_arm --logging_path logs/traj_bspline \
  --traj_initial logs/converted_trajs/bspline_traj --use_bspline \
  --num_control_points 30
```

*Note:* When using multiple workers for BSpline optimization, it is best to use `CMAstd`
as the optimizer. The default optimizers seem to have bugs (see
[issue](https://github.com/facebookresearch/nevergrad/issues/1593)).

### Visualize the designed trajectories

Make sure to use the same parameters for `num_timesteps` and `time_horizon` as were used
for the optimal trajectory design.

```bash
python3 scripts/visualize_trajectory.py --traj_parameter_path logs/traj
```

## Symbolic System ID

```bash
python3 scripts/symbolic_id.py --config-name one_link_arm_symbolic_id
```

## Collect joint data

```bash
python3 scripts/collect_joint_data.py --scenario_path models/iiwa_scenario.yaml \
  --traj_parameter_path logs/traj_bspline --save_data_path joint_data/iiwa
```

Add the `--use_hardware` flag to collect data on the real robot.

## Process collected joint data

The collected joint data will likely be quite noisy.

It can help to average joint data from executing the same trajectory multiple times
for improving the signal-to-noise ratio:

```bash
python3 scripts/average_joint_data.py joint_data_dir/ joint_data_averaged/
```

where `joint_data_dir` contains the joint data directories to average and
`joint_data_averaged` is the directory to write the averaged joint data to.

Filtering is very important and it is recommended to tune the parameters carefully.
Sweeping over different filter parameters can be helpful in this regard (see
sweeping section below).
Once filtering parameters have been determined, the data can be processed using the
`scripts/process_joint_data.py` script or by passing the parameters as arguments to
`scripts/solve_inertial_param_sdp.py` with the `--process_joint_data` flag.

After filtering, one might want to increase the data amount by combining the data from
multiple excitation trajectories. This can be achieved using
`scripts/concatenate_joint_data.py`.

## SDP System ID

Generates data, constructs the data matrix and solves the SDP using posidefinite
constraints on the pseudo inertias.
This requires trajectories that have been designed using optimal excitation trajectory
design as otherwise the numerics won't be good enough for the optimization to succeed.

Generating GT/ model-predicted data:

```bash
python3 scripts/solve_inertial_param_sdp.py --traj_parameter_path logs/traj \
  --num_data_points 5000 --use_one_link_arm
```

Note that the model-predicted data corresponds to simulation data from
`collect_joint_data.py` if the simulation timestep is set to zero (continuous-time
simulation). Otherwise, the simulation data will be slightly noisy and closer to real
robot data.

Using collected data (sim or real):

```bash
python3 scripts/solve_inertial_param_sdp.py --joint_data_path joint_data/iiwa_only \
  --process_joint_data
```

### Identifying the arm parameters and then freeze the parameters to identify the payload

First, identify the arm parameters without payload and save them to disk:

```bash
python3 scripts/solve_inertial_param_sdp.py --joint_data_path joint_data/iiwa_only \
  --process_joint_data --output_param_path identified_params/params.npy
```

Second, freeze the identified parameters and identify the payload:

```bash
python3 scripts/solve_inertial_param_sdp.py \
  --joint_data_path joint_data/iiwa_with_payload --process_joint_data \
  --initial_param_path identified_params/params.npy --payload_only
```

The payload inertial parameters should correspond to the last link parameters
identified by the second run minus the ones identified by the first run, i.e. the ones
stored in `identified_params/params.npy` and passed to the second run. This parameter
difference is printed by the script. Specify `--payload_frame_name` if you want to
print them in a particular frame.

## Reparameterized System ID

```bash
python3 scripts/identify_model.py --config-name iiwa_id
```

## Sweeping Parameters

### Eric ID

A sweep can be started with

```bash
wandb sweep config/sweep/iiwa_id_sweep.yaml
```

Individual agents for the sweep can be started using the printed `wandb agent` command.

### SDP data processing

The SDP results are very sensitive to the data processing. It can make sense to
sweep over the data processing parameters to identify the best parameters for one's
particular collected joint data.

A sweep can be started with

```bash
wandb sweep config/sweep/sdp_data_sweep.yaml
```

Individual agents for the sweep can be started using the printed `wandb agent` command.

### Parallel sweeps

A parallel sweep can be started with

```bash
bash scripts/parallel_sweep.sh config/sweep/sdp_data_sweep.yaml ${NUM_PARALLEL}
```

where `NUM_PARALLEL` is a variable containing the number of parallel runs. By default,
the maximum number of cores is used.

## Evaluation

Inertial ellipsoids can be visualized with `scripts/visualize_inertial_ellipsoids.py`.

## Credit

Any code in `franka_sysid/eric_id` has been copied/adopted from Eric Cousineau
([GitHub repo](https://github.com/EricCousineau-TRI/drake_sys_id)).
