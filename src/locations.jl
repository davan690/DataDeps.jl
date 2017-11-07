## Core path determining stuff

@static const default_loadpath ::Vector{String} = joinpath.([
    Pkg.Dir._pkgroot(), homedir(); # Common all systems

    if is_windows()
        vcat(get.(ENV,
           ["APPDATA", "LOCALAPPDATA",
            "ProgramData", "ALLUSERSPROFILE", # Probably the same, on all systems where both exist
            "PUBLIC", "USERPROFILE"], # Home Dirs ("USERPROFILE" is probably the same as homedir()
           [String[]])...)
    else
        ["/scratch", "/staging", # HPC common folders
         "/usr/share", "/usr/local/share"] # Unix Filestructure  
    end], "datadeps")

#ensure at least something in the loadpath exists.
mkpath(first(default_loadpath))



"""
    preferred_paths([calling_filepath])
    
returns the datadeps load_path
plus if calling_filepath is provided,
and is currently inside a package directory then it also includes the path to the dataseps in that folder. 
"""
function preferred_paths(calling_filepath="")
    cands = String[]
    pkg_deps_root = try_determine_package_datadeps_dir(calling_filepath)
    !isnull(pkg_deps_root) && push!(cands, get(pkg_deps_root))
    append!(cands, env_list("DATADEPS_LOAD_PATH", default_loadpath))
    cands
end

########################################################################################################################
## Package reletive path determining

"""
    try_determine_package_datadeps_dir(filepath)

Takes a path to a file.
If that path is in a package's folder,
Then this returns a path to the deps/data dir for that package (as a Nullable).
Which may or may not exist.
If not in a package returns null
"""
function try_determine_package_datadeps_dir(filepath)::Nullable{String}
    package_roots = [LOAD_PATH; Pkg.dir()]
    for root in package_roots
        if startswith(filepath, root)
            inner_path = filepath[length(root) + 1:end]
            first_pp, pkgname = (splitpath(inner_path))
            @assert(first_pp == "/", "expected \"\/\", got \"$(first_pp)\"")
            datadeps_dir = joinpath(root, pkgname,"deps","data")
            return Nullable(datadeps_dir)
        end
    end
    return Nullable{String}()
end

"""
    try_determine_package_datadeps_dir(::Void)

Fallback for if being run in some enviroment (eg the REPL),
where @__FILE__ is nothing.
Falls back to using the current directory.
So that if you are prototyping in the REPL (etc) for a package, 
and you are in the packages directory, then 
"""
function try_determine_package_datadeps_dir(::Void)
    try_determine_package_datadeps_dir(pwd())
end


####################################################################################################################
## Permission checking stuff

@enum AccessMode[UInt] F_OK=0b0000, X_OK=0b0001, W_OK=0b0010, XW_OK=0b0011, R_OK=0b0100, XR_OK=0b0101, WX_OK=0b0110, XWR_OK=0b0111

"""
    uv_access(path, mode)

Check access to a path.
Returns 2 results, first an error code (0 for all good), and second an error message.
https://stackoverflow.com/a/47126837/179081
"""
function uv_access(path, mode::AccessMode)
    local ret
    req = Libc.malloc(Base._sizeof_uv_fs)
    try
        ret = ccall(:uv_fs_access, Int32, (Ptr{Void}, Ptr{Void}, Cstring, CInt, Ptr{Void}), Base.eventloop(), req, path, mode, C_NULL)
        ccall(:uv_fs_req_cleanup, Void, (Ptr{Void},), req)
    finally
        Libc.free(req)
    end
    return ret, ret==0 ? "OK" : Base.struverror(ret)
end

##########################################################################################################################
## Actually determining path being used (/going to be used) by a given datadep


"""
    determine_save_path(name)

Determines the location to save a datadep with the given name to.
"""
function determine_save_path(name, calling_filepath="")::String
    cands = preferred_paths(calling_filepath)
    path = findfirst(cands) do path
        0 == first(uv_access(path, AccessMode.W_OK))
    end
    if path==0
        error("No possible save path")
    end
    return joinpath(cands[path_ind], name)
end

"""
    try_determine_load_path(name)

Trys to find a local path to the datadep with the given name.
If it fails then it returns nothing.
"""
function try_determine_load_path(name, calling_filepath="")::Nullable{String}
    cands = [pwd(); preferred_paths(calling_filepath)]
    cands = joinpath.(cands, name)
    path_ind = findfirst(cands) do path
        0 == first(uv_access(path, AccessMode.R_OK))
    end
    if path==0
        Nullable{String}()
    else
        Nullable(joinpath(cands[path_ind], name))
    end
end
