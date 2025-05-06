struct CameraData {
	cameraPosition : vec3<f32>,	// 0
	apertureSize : f32,			// 12

	targetPosition : vec3<f32>,	// 16
	focusDistance : f32,		// 28

	aspectRatio : f32,			// 32
	numSamples : u32,			// 36
	_pad3 : f32,				// 40
	_pad4 : f32,				// 44

	// total 48
};

struct Object {
	position : vec3<f32>,
	radius : f32,
	
	color : vec3<f32>,
	objectType : u32,
  
	normal: vec3<f32>, // plane normal or orientation
	height: f32, // cylinder
  
	size: vec3<f32>, // box half-extents
	materialIndex: u32
};

struct Material {
	albedo: vec3<f32>,      // Base color
	roughness: f32,         // For future PBR or glossy shading

	emissive: vec3<f32>,    // Light emitted by surface
	metallic: f32,          // For future PBR

	usesTexture: u32,       // If true, use texture instead of color
	textureIndex: u32,      // Index into texture array
	reflectivity : f32,
	_pad1 : u32,

	// Add more fields as needed: reflectivity, ior, transparency, etc.
}

const OBJTYPE_SPHERE : u32 = 0u;
const OBJTYPE_PLANE : u32 = 1u;
const OBJTYPE_BOX : u32 = 2u;

@group(0) @binding(0) var storageImage : texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(1) var<uniform> cameraData : CameraData;
@group(0) @binding(2) var<storage, read> objects : array<Object>;
@group(0) @binding(3) var<storage, read> materials: array<Material>;
@group(0) @binding(4) var texSampler: sampler;
@group(0) @binding(5) var textures: texture_2d_array<f32>;

fn getMaterialColor(mat: Material, uv: vec2<f32>) -> vec3<f32> {
    
	if (mat.usesTexture == 1u) {
		let texSize = textureDimensions(textures);		
		let uvWrapped = fract(uv);
		let pixelCoord = vec2<i32>(uvWrapped * vec2<f32>(texSize));
		let color = textureLoad(textures, pixelCoord, i32(mat.textureIndex), 0).rgb;
		return color;
    }
	
    return mat.albedo;
}

struct Ray {
	origin: vec3<f32>, // ray origin
	direction: vec3<f32> // ray direction
}

struct HitResult {
	hit: bool,               // Did the ray hit something?
	t: f32,                  // Distance to hit
	position: vec3<f32>,     // World-space hit point
	normal: vec3<f32>,       // Surface normal at hit
	materialIndex: u32,      // For looking up materials/colors	
	color: vec3<f32>,        // Color at the hit point	
}

fn noHit() -> HitResult {
	return HitResult(
		false,           // hit
		1e30,            // t (a very large number)
		vec3<f32>(0.0),  // position
		vec3<f32>(0.0),  // normal
		0u,              // materialIndex		
		vec3<f32>(0.0),  // color
	);
}

fn intersectSphere(ray:Ray, obj:Object) -> HitResult {
	var hit = false;
	let sphere = obj;
	let oc = ray.origin - sphere.position;
	let a = dot(ray.direction, ray.direction);
	let b = 2.0 * dot(oc, ray.direction);
	let c = dot(oc, oc) - sphere.radius * sphere.radius;
	let discriminant = b*b - 4.0*a*c;

	if (discriminant < 0.0) {
		return noHit();
	}

	let sqrtD = sqrt(discriminant);
	let t1 = (-b - sqrtD) / (2.0 * a);  
	let t2 = (-b + sqrtD) / (2.0 * a);
	let t = select(t2, t1, t1 > 0.0);

	if (t < 0.0) {
		return noHit();
	}

	let hitPos = ray.origin + ray.direction * t;

	let local = normalize(hitPos - sphere.position);
	let u = 0.5 + atan2(local.z, local.x) / (2.0 * 3.1415926);
	let v = 0.5 - asin(local.y) / 3.1415926;
	let uv = vec2<f32>(u, v);
	return HitResult(
		true,           // hit
		t, 
		hitPos, 
		normalize(hitPos - sphere.position), // normal
		obj.materialIndex,              // materialIndex		
		getMaterialColor(materials[obj.materialIndex], uv)
	);
}

fn intersectPlane(ray: Ray, obj:Object) -> HitResult {
	let denom = dot(ray.direction, obj.normal);
	if (abs(denom) < 1e-5) {
		return noHit(); // Parallel
	}

	let t = dot(obj.position - ray.origin, obj.normal) / denom;
	if (t < 0.0) {
		return noHit(); // Behind ray origin
	}

	let hitPos = ray.origin + ray.direction * t;
		
	let localPos = hitPos - obj.position;
	let uv = vec2<f32>(localPos.x, localPos.z) * 0.2;

	let color = getMaterialColor(materials[obj.materialIndex], uv);

	return HitResult(
		true,           // hit
		t, 
		hitPos, 
		obj.normal, 
		obj.materialIndex,              // materialIndex		
		color
	);
}

fn buildRotationMatrix(obj:Object) -> mat3x3<f32> {
	let forward = normalize(obj.normal);
	let up = vec3<f32>(0.0, 1.0, 0.0);
	let right = normalize(cross(forward, up));
	let newUp = cross(right, forward);

	return mat3x3<f32>(
		right,
		newUp,
		-forward
	);
}

fn intersectBox(ray: Ray, obj: Object) -> HitResult {
	let center = obj.position;
	let halfSize = obj.size;
	var boxRotation = buildRotationMatrix(obj);

	// Transform ray into box local space
	let invRot = transpose(boxRotation); // inverse of orthonormal matrix is transpose

	let rayOriginLocal = invRot * (ray.origin - center);
	let rayDirLocal = invRot * ray.direction;

	// AABB intersection in local space
	let minB = -halfSize;
	let maxB = halfSize;

	var tMin = (minB - rayOriginLocal) / rayDirLocal;
	var tMax = (maxB - rayOriginLocal) / rayDirLocal;

	let t1 = min(tMin, tMax);
	let t2 = max(tMin, tMax);

	let tNear = max(max(t1.x, t1.y), t1.z);
	let tFar = min(min(t2.x, t2.y), t2.z);

	if (tNear > tFar || tFar < 0.0) {
		return noHit();
	}

    let t = select(tFar, tNear, tNear > 0.0);
    let localHitPos = rayOriginLocal + rayDirLocal * t;

    // Determine normal in local space
    var localNormal = vec3<f32>(0.0);
    let bias = 1e-4;
    if (abs(localHitPos.x - maxB.x) < bias) {
        localNormal = vec3<f32>(1.0, 0.0, 0.0);
    } else if (abs(localHitPos.x - minB.x) < bias) {
        localNormal = vec3<f32>(-1.0, 0.0, 0.0);
    } else if (abs(localHitPos.y - maxB.y) < bias) {
        localNormal = vec3<f32>(0.0, 1.0, 0.0);
    } else if (abs(localHitPos.y - minB.y) < bias) {
        localNormal = vec3<f32>(0.0, -1.0, 0.0);
    } else if (abs(localHitPos.z - maxB.z) < bias) {
        localNormal = vec3<f32>(0.0, 0.0, 1.0);
    } else if (abs(localHitPos.z - minB.z) < bias) {
        localNormal = vec3<f32>(0.0, 0.0, -1.0);
    }

    let worldNormal = boxRotation * localNormal;
    let worldHitPos = ray.origin + ray.direction * t;

    return HitResult(
		true,           // hit
		t, 
		worldHitPos, 
		normalize(worldNormal),
		obj.materialIndex,              // materialIndex		
		getMaterialColor(materials[obj.materialIndex], vec2<f32>(0,0))
    );
}

fn intersectObject(ray:Ray, obj:Object) -> HitResult {
	if (obj.objectType == OBJTYPE_SPHERE) {
		return intersectSphere(ray, obj);
	} else if (obj.objectType == OBJTYPE_PLANE) {    
		return intersectPlane(ray, obj);
	} else if (obj.objectType == OBJTYPE_BOX) {    
		return intersectBox(ray, obj);
	} else {
		return noHit(); // Unknown object type
	}
}

fn rand(coord: vec2<u32>, seed: u32) -> f32 {
    let p = vec2<f32>(f32(coord.x + seed), f32(coord.y + seed));
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn sampleDisk(rand1: f32, rand2: f32) -> vec2<f32> {
    let r = sqrt(rand1);
    let theta = 6.2831853 * rand2;
    return r * vec2<f32>(cos(theta), sin(theta));
}

@compute @workgroup_size(8,8)
fn main(@builtin(global_invocation_id) global_id : vec3<u32>) {
	let imgSize = vec2<u32>(textureDimensions(storageImage));
	if (global_id.x >= imgSize.x || global_id.y >= imgSize.y) { return; }

	let samplesPerPixel = cameraData.numSamples; //8u;
	var color = vec3<f32>(0.0);

	for (var s = 0u; s < samplesPerPixel; s = s + 1u) {
		// jittered UV for anti-aliasing
		let jitter = vec2<f32>(
			rand(global_id.xy, s * 2u),
			rand(global_id.xy, s * 2u + 1u)
		);
		let uvJittered = (vec2<f32>(f32(global_id.x), f32(imgSize.y - 1u - global_id.y)) + jitter) / vec2<f32>(f32(imgSize.x), f32(imgSize.y));
		let uv2 = uvJittered * 2.0 - vec2<f32>(1.0);

		// rest of your ray generation + shading logic goes here
		// use uv2 instead of the original uv

		let sensorX = uv2.x * cameraData.aspectRatio;
		let sensorY = uv2.y;

		let forward = normalize(cameraData.targetPosition - cameraData.cameraPosition);
		let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
		let up = cross(forward, right);

		// dof
		let rayDir = normalize(forward + sensorX * right + sensorY * up);
		let focusPoint = cameraData.cameraPosition + rayDir * cameraData.focusDistance;
		let lensOffset2D = sampleDisk(rand(global_id.xy, s*17u), rand(global_id.xy, s*31u)) * cameraData.apertureSize;
		let lensOffset = right*lensOffset2D.x + up*lensOffset2D.y;

		let ro = cameraData.cameraPosition + lensOffset;
		let rd = normalize(focusPoint-ro);

		// no dof
		// let rayDir = normalize(forward + sensorX * right + sensorY * up);
		// let ro = cameraData.cameraPosition;
		// let rd = rayDir;

		let ray = Ray(ro, rd);

		

		var hit = false;

		var hitIdx:u32 = 0;
		var bestHit = noHit();
		for (var i = 0u; i < arrayLength(&objects); i = i + 1u) {
			let obj = objects[i];
			let hit = intersectObject(ray, obj);
			if (hit.hit && hit.t < bestHit.t) {
				bestHit = hit;
				hitIdx = i;
			}
		}

		var hitColor = vec3<f32>(47/255.0, 144/255.0, 250/255.0); // default sky color
		var lightPosition = cameraData.cameraPosition; //vec3<f32>(100, 100, 100); //-0.5, 1.0, -0.5);
		lightPosition.y = 100;

		if (bestHit.hit) {
			let mat = materials[bestHit.materialIndex];
			let baseColor = pow(bestHit.color, vec3<f32>(1.0 / 2.2));

			var shadow = false;
			// Offset the hit point slightly to avoid self-intersection ("shadow acne")
			let shadowRayOrigin = bestHit.position + 0.001 * bestHit.normal;
			let shadowRayDir = normalize(lightPosition - shadowRayOrigin);
			let shadowRay = Ray(shadowRayOrigin, shadowRayDir);

			let lightDist = length(lightPosition - shadowRayOrigin);

			for (var i = 0u; i < arrayLength(&objects); i = i + 1u) {
				let obj = objects[i];
				if (i == hitIdx) { continue; }
				let shadowHit = intersectObject(shadowRay, obj);
				if (shadowHit.hit && shadowHit.t < lightDist) {
					shadow = true;
					break;
				}
			}

			let hitPos = bestHit.position;
			let lightDir = normalize(lightPosition);
			let viewDir = normalize(cameraData.cameraPosition - hitPos);
			let reflectDir = reflect(-lightDir, bestHit.normal);

			let diffuse = max(dot(bestHit.normal, lightDir), 0.0);
			let ambient = 0.2;
			var lighting = ambient;

			var specular = 0.0;
			if (!shadow) {
				lighting += (1.0 - ambient) * diffuse;

				let specularStrength = 0.5;
				let shininess = 32.0;
				let specAngle = max(dot(viewDir, reflectDir), 0.0);
				specular = specularStrength * pow(specAngle, shininess);

				hitColor = baseColor * lighting + vec3<f32>(specular);
			} else {
				hitColor = baseColor * lighting;
			}			
		}

		color = color + hitColor; // hitColor = result from your per-ray shading
	}	
    
	color = color / f32(samplesPerPixel);
	textureStore(storageImage, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}