using Base.Test
using DataDeps: try_determine_load_path, determine_save_path, try_determine_package_datadeps_dir


@testset "package data deps dir" begin
    target = joinpath(realpath(joinpath(dirname(@__FILE__),"..")),"deps","data")
    @test try_determine_package_datadeps_dir(@__FILE__) |> get == target

    mktemp() do fn, fh
        @test try_determine_package_datadeps_dir(fn) |> isnull
    end

end
