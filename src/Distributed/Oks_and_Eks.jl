
function compute_importance_weights(logψs, logpcs)
    log_ratios =  2 .* real.(logψs) .- logpcs
    logZ = logsumexp(log_ratios) - log(length(logpcs))
    return exp.(log_ratios .- logZ)
end

function generate_Oks_and_Eks(peps::PEPS, ham::OpSum; kwargs...)
    hilbert = siteinds(peps)
    ham_op = TensorOperatorSum(ham, hilbert)
    return generate_Oks_and_Eks(peps, ham_op; kwargs...)
end

function generate_Oks_and_Eks(peps::PEPS, ham_op::TensorOperatorSum; 
                              threaded=false, multiproc=false, shared_array=true, async_double_layers=false, verbose=false,
                              kwargs...)
    
    local double_layer_update, stop_thread
    if async_double_layers
        double_layer_update, stop_thread = generate_async_double_layer_envs(peps; verbose)
    else
        double_layer_update = update_double_layer_envs!
    end

    local Oks_and_Eks_func
    
    if multiproc
        if shared_array
            Oks_and_Eks_func = generate_Oks_and_Eks_multiproc_sharedarrays(peps, ham_op; threaded, double_layer_update, kwargs...)
        else
            Oks_and_Eks_func = generate_Oks_and_Eks_multiproc(peps, ham_op; threaded, double_layer_update, kwargs...)
        end
    elseif threaded
        Oks_and_Eks_func = generate_Oks_and_Eks_threaded(peps, ham_op; double_layer_update, kwargs...)
    else
        Oks_and_Eks_func = generate_Oks_and_Eks_singlethread(peps, ham_op; double_layer_update, kwargs...)
    end

    if async_double_layers
        return Oks_and_Eks_func, stop_thread
    end

    return Oks_and_Eks_func
end


###### Single threaded
# this function returns a Ok_and_Eks function wich can be used to optimise via QNG.evolve
function generate_Oks_and_Eks_singlethread(peps::PEPS, ham_op::TensorOperatorSum;
                                           timer=TimerOutput(), double_layer_update=update_double_layer_envs!,
                                           kwargs...)
    function Oks_and_Eks_(Θ::Vector{T}, sample_nr::Integer; kwargs2...) where T
        if length(kwargs2) > 0
            kwargs_new = Dict{Symbol,Any}() # Fix of bug in julias merge function
            kwargs = merge(kwargs_new, kwargs, kwargs2)
        end
        write!(peps, Θ)
        @timeit timer "double_layer_envs" double_layer_update(peps) # update the double layer environments once for the peps 
        
        return Oks_and_Eks_singlethread(peps, ham_op, sample_nr; timer=timer, kwargs...)
    end
    return Oks_and_Eks_
end

# The central function is Oks and Eks
function Oks_and_Eks_singlethread(peps::PEPS, ham_op::TensorOperatorSum, sample_nr::Integer; timer=TimerOutput(), kwargs...)
    eltype_ = eltype(peps)
    eltype_real = real(eltype_)
    
    Oks = Matrix{eltype_}(undef, length(peps), sample_nr)
    Eks = Vector{eltype_}(undef, sample_nr)
    logψs = Vector{Complex{eltype_real}}(undef, sample_nr)
    samples = Vector{Matrix{Int}}(undef, sample_nr)
    logpc = Vector{eltype_real}(undef, sample_nr)
    contract_dims = Vector{Int}(undef, sample_nr)

    for i in 1:sample_nr
        Ok_view = @view Oks[:, i]
        _, Eks[i], logψs[i], samples[i], logpc[i], contract_dims[i] = Ok_and_Ek(peps, ham_op; timer, Ok=Ok_view, kwargs...)
        
    end
    
    #return Ok, E_loc, logψ, samples, compute_importance_weights(logψ, logpc)
    Dict(:Oks => transpose(Oks), :Eks => Eks, :logψs => logψs, :samples => samples, :weights => compute_importance_weights(logψs, logpc), :contract_dims => contract_dims)
    # returns Gradient, local Energy, log(<ψ|S>), samples S, p
end

include("double_layer_async.jl")
include("Oks_and_Eks_threaded.jl")
include("Oks_and_Eks_multiproc.jl")
include("Oks_and_Eks_sharedarray.jl")