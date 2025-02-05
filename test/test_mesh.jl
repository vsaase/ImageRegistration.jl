
println("testing mesh")
# function test_mesh()
img = rand(100,100)
offset = [0,0]
dist = 20
mesh = create_mesh(img, offset, dist)
i1 = 100 % (dist*sin(pi/3)) / 2
@test mesh.src_nodes[1,:] ≈ [i1,0]
@test mesh.src_nodes[2,:] ≈ [i1,20]
@test mesh.src_nodes[3,:] ≈ [i1,40]
@test mesh.src_nodes[4,:] ≈ [i1,60]
@test mesh.src_nodes[5,:] ≈ [i1,80]
@test mesh.src_nodes[6,:] ≈ [i1,100]
@test mesh.src_nodes[7,:] ≈ [i1 + 20*(sin(pi/3)), 10]
@test maximum(mesh.src_nodes[:,1]) <= 100
@test maximum(mesh.src_nodes[:,2]) <= 100
@test size(mesh.src_nodes, 1) == 33
# test that src_nodes match dst_nodes, initially
function wrapper() # otherwise gives warning if a and b are already defined globally
	for (a, b) in zip(mesh.src_nodes, mesh.dst_nodes)
		@test a == b
	end
end
wrapper()
@test size(mesh.edges, 2) == 81
