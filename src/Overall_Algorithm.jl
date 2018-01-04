###############################################################################
#                                                                             #
#  This file is part of the julia module for Multi Objective Optimization     #
#  (c) Copyright 2017 by Aritra Pal, Hadi Charkhgard                          #
#                                                                             #
# This license is designed to guarantee freedom to share and change software  #
# for academic use, but restricting commercial firms from exploiting our      #
# knowhow for their benefit. The precise terms and conditions for using,      #
# copying, distribution, and modification follow. Permission is granted for   #
# academic research use. The license expires as soon as you are no longer a   # 
# member of an academic institution. For other uses, contact the authors for  #
# licensing options. Every publication and presentation for which work based  #
# on the Program or its output has been used must contain an appropriate      # 
# citation and acknowledgment of the authors of the Program.                  #
#                                                                             #
# The above copyright notice and this permission notice shall be included in  #
# all copies or substantial portions of the Software.                         #
#                                                                             #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR  #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,    #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER      #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING     #
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER         #
# DEALINGS IN THE SOFTWARE.                                                   #
#                                                                             #
###############################################################################

include("starting_solution_creators.jl")
include("feasibility_pumping.jl")
include("local_search_operators.jl")
include("decomposition_heuristics.jl")
include("solution_polishing.jl")

###############################################################################
# Computing the Non Dominated Frontier                                        #
###############################################################################

###############################################################################
## Approximate Algorithms                                                    ##
###############################################################################

###############################################################################
### Multiobjective Mixed Binary Programs                                    ###
###############################################################################

@inbounds function fpbhcplex(instance::Union{BOBPInstance, BOMBLPInstance, MOBPInstance, MOMBLPInstance}; obj_fph::Bool=true, local_search::Bool=true, decomposition::Bool=true, solution_polishing::Bool=true, threads::Int64=1, parallelism::Bool=false, timelimit::Float64=120.0, time_ratio::Float64=2/3)
    t0 = time()
    
    params = Dict()
    params[:obj_fph] = obj_fph
    params[:local_search] = local_search
    params[:decomposition] = decomposition
    params[:solution_polishing] = solution_polishing
    params[:total_threads] = threads
    params[:parallelism] = parallelism
    params[:timelimit] = timelimit
    params[:time_ratio] = time_ratio
    
    instance2, bin_var_ind = lprelaxation(instance)
    timelimit = copy(params[:timelimit])
    if params[:solution_polishing]
        params[:timelimit] = params[:time_ratio]*params[:timelimit]
    end
    model = cplex_model(instance2, 1)
    if !params[:decomposition]
        non_dom_sols = FPH(instance2, model, bin_var_ind, params)
    else
        if typeof(instance) == MOBPInstance || typeof(instance) == MOMBLPInstance
            non_dom_sols = MFPSM(instance2, model, bin_var_ind, params)
        end
        if typeof(instance) == BOBPInstance || typeof(instance) == BOMBLPInstance
            non_dom_sols = MPSM(instance2, model, bin_var_ind, params)
        end
    end
    if params[:solution_polishing]
        params[:timelimit] = timelimit - (time()-t0)
        if params[:timelimit] < (1.0-params[:time_ratio])*timelimit
            params[:timelimit] = (1.0-params[:time_ratio])*timelimit
        end
        non_dom_sols = SOL_POL(instance2, model, bin_var_ind, non_dom_sols, params)
    end
    params[:timelimit] = timelimit
    if typeof(instance) == BOMBLPInstance || typeof(instance) == MOMBLPInstance
        non_dom_sols = check_feasibility(non_dom_sols, instance)
    end
    select_and_sort_non_dom_sols(non_dom_sols)
end

###############################################################################
# Wrappers for JuMP Model                                                     #
###############################################################################

@inbounds function fpbhcplex(model::JuMP.Model; obj_fph::Bool=true, local_search::Bool = true, decomposition::Bool=true, solution_polishing::Bool=true, threads::Int64=1, parallelism::Bool=false, timelimit::Float64=120.0, time_ratio::Float64=2/3)
    t0 = time()
    instance, sense = read_an_instance_from_a_jump_model(model)
    if typeof(instance) in [BOLPInstance, MOLPInstance]
        println("Problem has no Binary or Integer variables")
        return 
    else
        non_dom_sols = fpbhcplex(instance, obj_fph=obj_fph, local_search=local_search, decomposition=decomposition, solution_polishing=solution_polishing, parallelism=parallelism, threads=threads, timelimit=timelimit, time_ratio=time_ratio)
    end
    if :Max in sense
        for i in 1:length(non_dom_sols), j in 1:length(sense)
            if sense[j] == :Max
                if typeof(instance) == BOBPInstance || typeof(instance) == BOMBLPInstance
                    if j == 1
                        non_dom_sols[i].obj_val1 = -1.0*non_dom_sols[i].obj_val1
                    else
                        non_dom_sols[i].obj_val2 = -1.0*non_dom_sols[i].obj_val2
                    end                        
                else
                    non_dom_sols[i].obj_vals[j] = -1.0*non_dom_sols[i].obj_vals[j]
                end
            end
        end
    end
    non_dom_sols
end

@inbounds function fpbhcplex(filename::String, sense::Vector{Symbol}; obj_fph::Bool=true, local_search::Bool=true, decomposition::Bool=true, solution_polishing::Bool=true, threads::Int64=1, parallelism::Bool=false, timelimit::Float64=120.0, time_ratio::Float64=2/3)
    t0 = time()
    instance, sense = read_an_instance_from_a_lp_or_a_mps_file(filename, sense)
    if typeof(instance) in [BOLPInstance, MOLPInstance]
        println("Problem has no Binary or Integer variables")
        return 
    else
        non_dom_sols = fpbhcplex(instance, obj_fph=obj_fph, local_search=local_search, decomposition=decomposition, solution_polishing=solution_polishing, parallelism=parallelism, threads=threads, timelimit=timelimit, time_ratio=time_ratio)
    end
    if :Max in sense
        for i in 1:length(non_dom_sols), j in 1:length(sense)
            if sense[j] == :Max
                if typeof(instance) == BOBPInstance || typeof(instance) == BOMBLPInstance
                    if j == 1
                        non_dom_sols[i].obj_val1 = -1.0*non_dom_sols[i].obj_val1
                    else
                        non_dom_sols[i].obj_val2 = -1.0*non_dom_sols[i].obj_val2
                    end                        
                else
                    non_dom_sols[i].obj_vals[j] = -1.0*non_dom_sols[i].obj_vals[j]
                end
            end
        end
    end
    non_dom_sols
end
