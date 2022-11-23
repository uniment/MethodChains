using REPL


function init_repl()
#    mode = get(ENV, "JULIA_METHOD_CHAIN", "auto")
#    if mode == "auto"
#        if isdefined(Main, :IJulia)
#            Main.IJulia.push_preexecute_hook(revise)
#        else

    function _method_chains_first(ex)
        Internals.method_chains!(ex)
    end


    pushfirst!(REPL.repl_ast_transforms, _method_chains_first)
    # #664: once a REPL is started, it no longer interacts with REPL.repl_ast_transforms
    iter = 0
    # wait for active_repl_backend to exist
    ts=0:0.05:2
    for t ∈ ts
        sleep(step(ts))
        if isdefined(Base, :active_repl_backend)
            push!(Base.active_repl_backend.ast_transforms, _method_chains_first)
            break
        end
    end
    isdefined(Base, :active_repl_backend) || 
        @warn("active_repl_backend not defined; interactive-mode MethodChains might not work.")
#        end
#        if isdefined(Main, :Atom)
#            Atom = getfield(Main, :Atom)
#            if Atom isa Module && isdefined(Atom, :handlers)
#                setup_atom(Atom)
#            end
#        end
#    end
    nothing
end
