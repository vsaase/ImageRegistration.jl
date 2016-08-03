"""
`IMWARP` - Apply affine transform to image using bilinear interpolation

    warped_img, warped_offset = imwarp(img, tform, offset)

* `img`: 2D array, image (todo: extend to Image type)
* `tform`: 3x3 matrix, affine transform (defined as row vector x matrix)
* `offset`: 2-element array, position of img[1,1] in global space
* `warped_img`: with pixel values the same type as original image (for Int type, 
  pixel values are rounded)
* `warped_offset`: 2-element array, position of warped_img[1,1] in global space

The bounding box of the warped image is defined as the smallest
integer-valued rectangle that contains the affine transform of the
bounding box of the original image.

This means that `warped_offset` is constrained to be integer-valued,
though `offset` is allowed to have floating point values.  The integer
constraint removes the need for further interpolation in any
subsequent fusing of multiple warped tiles.

Bilinear interpolation, with extrapolation using zero fill value.

### Definitions

Global position of `img` pixels (analogous definitions for `warped_img`): 
  
* [1,1] pixel has position (offset[1] - 0.5, offset[2] - 0.5) in global space
* [i,j] pixel has position (offset[1]+i-0.5, offset[2]+j-0.5)  

e.g. with no offset, [i, j] pixel has median([i-1:i, j-1:j]) location in global space.

Affine transform of a global position:

* homogeneous coordinates [x, y, 1]  [ax + by + c, dx + ey + f, 1]
* or equivalently [x, y, 1]  [x, y, 1] * tform

        where `tform` = [a d 0;  
                         b e 0;  
                         c f 1]

Note that:

1. transform is *row* vector x matrix (right hand side matrix multiplication)
2. definition compatible with [MATLAB](http://www.mathworks.com/help/images/ref/affine2d-class.html), but not AffineTransforms.jl
3. meaning of transform depends on whether the image is in ij or xy format

Affine transform of an image (two equivalent definitions, provide scaling isn't an issue):

1. The value of `img` at a position is equal to the value of
the `warped_img` at the transformed position. 
2. The value of `warped_img` at a position is equal to the value of
`img` at the inverse transformed position.  

We apply definition 2 as it's compatible with gridding and interpolation.

Bounding box of an image of size (m,n):

* smallest rectangle in global space that contains the positions of the [1,1] 
  and [m,n] pixels
* represented by the 4-tuple (offset[1],offset[2],m,n)

    (offset[1],offset[2])  ___________
                          |           |
                    height|           |
                       m  |           |
                          |___________|
                                n      (offset[1]+m,offset[2]+n)
                              width

""" 
function imwarp{T}(img::Union{Array{T}, SharedArray{T}}, tform, offset=[0.0,0.0])
  bb = BoundingBox{Float64}(offset..., size(img, 1), size(img, 2))
  wbb = tform_bb(bb, tform)
  tbb = snap_bb(wbb)
  warped_img = zeros(T, tbb.h, tbb.w)
  return imwarp!(warped_img, img, tform, offset)
end

function imwarp!{T}(warped_img::Union{Array{T}, SharedArray{T}}, img::Union{Array{T}, SharedArray{T}}, tform, offset=[0.0,0.0])
  # img bb rooted at offset, with height and width calculated from image
  bb = BoundingBox{Float64}(offset..., size(img, 1), size(img, 2))
  # transform original bb to generate new bb (may contain continuous values)
  wbb = tform_bb(bb, tform)
  # snap transformed bb to the nearest exterior integer values
  tbb = snap_bb(wbb)
  # construct warped_img, pixels same Type as img, size calculated from tbb
  # WARNING: should have zero values, but unclear whether guaranteed by similar
  # warped_img = similar(img, tbb.h+1, tbb.w+1)
  #warped_img = zeros(T, tbb.h, tbb.w)
  if size(warped_img) != (tbb.h, tbb.w)
#    println("The supplied output array size is incorrect. Expected $(tbb.h, tbb.w) but got $(size(warped_img)). Aborting.")
    println("The supplied output array size is incorrect. Aborting")
    return;
  end
  # offset of warped_img from the global origin
  warped_offset = [tbb.i, tbb.j]
  #tform[3, 1:2] -= 1.0
  M = inv(tform)   # inverse transform in global space
#  M[3,1:2] -= offset'-1.0   # include conversion to pixel space of original img
  M[3,1:2] -= offset'-0.5   # include conversion to pixel space of original img

  # cycle through all the pixels in warped_img
  for j = 1:size(warped_img,2)
    for i = 1:size(warped_img,1) # cycle through column-first for speed
        # convert from pixel to global space
        # (we index to zero, then add on the offset)
        u, v = i-0.5+warped_offset[1], j-0.5+warped_offset[2]
        # apply inv(tform), conversion back to pixel space included
        # x, y = [u, v, 1] * M - but writing it out moves faster
        x, y = M[1,1]*u + M[2,1]*v + M[3,1], M[1,2]*u + M[2,2]*v + M[3,2]
        # x, y = M[1,1]*u + M[1,2]*v + M[1,3], M[2,1]*u + M[2,2]*v + M[2,3]  # faster but differs by a matrix transpose

        # Slow...
        #warped_img[i,j] = round(Uint8, bilinear(img, x, y))
        #warped_img[i,j] = bilinear(img, x, y)
        # Bilinear interpolation
        fx, fy = floor(Int64, x), floor(Int64, y)
        wx, wy = x-fx, y-fy
	rwx, rwy = 1.0 - wx, 1.0 - wy
        # if 1 <= fx && fx+1 <= size(img, 1) && 1 <= fy && fy+1 <= size(img, 2)
        if 1 <= fx <= size(img, 1) - 1 && 1 <= fy <= size(img, 2) -1   # normal case
                # Expansion of p = [1-wx wx] * img[fx:fx+1, fy:fy+1] * [1-wy; wy]
                @fastmath @inbounds pff = rwy * rwx * img[fx,fy]
                @fastmath @inbounds pxf = rwy * wx * img[fx+1,fy]
		@fastmath @inbounds pfy = wy * rwx * img[fx,fy+1] 
		@fastmath @inbounds pxy = wy * wx * img[fx+1,fy+1]
		@fastmath p = pff + pxf + pfy + pxy;
	else
	  if 1 <= fx <= size(img, 1) - 1
		if fy == 0
		@fastmath @inbounds pfy = wy * rwx * img[fx,fy+1] 
		@fastmath @inbounds pxy = wy * wx * img[fx+1,fy+1]
		@fastmath p = pfy + pxy;
		elseif fy == size(img, 2)
                @fastmath @inbounds pff = rwy * rwx * img[fx,fy]
                @fastmath @inbounds pxf = rwy * wx * img[fx+1,fy]
		@fastmath p = pff + pxf;
	    	else p = 0;
	      end
	  elseif 1 <= fy <= size(img, 2) - 1
	    	if fx == 0
                @fastmath @inbounds pxf = rwy * wx * img[fx+1,fy]
		@fastmath @inbounds pxy = wy * wx * img[fx+1,fy+1]
		@fastmath p = pxf + pxy;
		elseif fx == size(img, 1)
                @fastmath @inbounds pff = rwy * rwx * img[fx,fy]
		@fastmath @inbounds pfy = wy * rwx * img[fx,fy+1] 
		@fastmath p = pff + pfy;
	    	else p = 0;
	      end
	    elseif fx == 0 && fy == 0
		@fastmath @inbounds p = wy * wx * img[fx+1,fy+1]
	    elseif fx == 0 && fy == size(img, 2)
                @fastmath @inbounds p = rwy * wx * img[fx+1,fy]
	    elseif fx == size(img, 1) && fy == 0
		@fastmath @inbounds p = wy * rwx * img[fx,fy+1] 
	    elseif fx == size(img, 1) && fy == size(img, 2)
                @fastmath @inbounds p = rwy * rwx * img[fx,fy]
	    else p = 0;
	  end
	end	
	writepixel(warped_img, i, j, p);
      end
    end
  warped_img, warped_offset
end

function writepixel{T<:Integer}(img::Array{T},i,j,pixelvalue)
  @inbounds img[i,j]=round(T,pixelvalue)
end

function writepixel{T<:FloatingPoint}(img::Array{T},i,j,pixelvalue)
   @inbounds img[i,j]=pixelvalue
end

function writepixel{T<:Integer}(img::SharedArray{T},i,j,pixelvalue)
	@fastmath @inbounds img[i,j]=round(T,pixelvalue)
end

function writepixel{T<:FloatingPoint}(img::SharedArray{T},i,j,pixelvalue)
   @inbounds img[i,j]=pixelvalue
end

function writepixel{T<:Integer}(img::SharedArray{T},i,j,pixelvalue)
  img[i,j]=round(T,pixelvalue)
end

function writepixel{T<:FloatingPoint}(img::SharedArray{T},i,j,pixelvalue)
  img[i,j]=pixelvalue
end
  
