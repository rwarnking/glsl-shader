///////////////////////////////////////////////////////////////////////////////////////////////////
// Keybindings
///////////////////////////////////////////////////////////////////////////////////////////////////
const KEY_MAT_AIR = 'Digit1';
const KEY_MAT_WATER = 'Digit2';
const KEY_MAT_GLASS = 'Digit3';
const KEY_MAT_DIAMOND = 'Digit4';

///////////////////////////////////////////////////////////////////////////////////////////////////
// Globals
///////////////////////////////////////////////////////////////////////////////////////////////////
let containerDims = [5.5, 5.5, 15.0]; // TODO vec3 const

///////////////////////////////////////////////////////////////////////////////////////////////////
// Classes
///////////////////////////////////////////////////////////////////////////////////////////////////
class Ball {
    constructor(
    	size=0.0, position=vec3.fromValues(0.0, -1.0, 0.0), 
		speed=0.0, temperature=22.0
    ) {
        this.s = size;
        this.pos = position;
        this.posMax = vec3.create();
        vec3.copy(this.posMax, position);
        this.temp = temperature;
    }
    
    getInfo() {
        return [this.pos[0], this.pos[1]*containerDims[1], this.pos[2], this.s];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Setup
///////////////////////////////////////////////////////////////////////////////////////////////////
const balls = [
    new Ball(1.5),
    new Ball(),
    new Ball(),
    new Ball(),
    new Ball()
];

///////////////////////////////////////////////////////////////////////////////////////////////////
// Texture Setup
///////////////////////////////////////////////////////////////////////////////////////////////////
function makeTexture(target, img, gl, tex) {
    // this specific image is flipped
    //gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
	gl.texImage2D(target, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
	gl.generateMipmap(gl.TEXTURE_CUBE_MAP);
}

// declare textuer here so we can pass it to uniform function
const tex = this.gl().createTexture();

const faceInfos = [
    {
        target: this.gl().TEXTURE_CUBE_MAP_POSITIVE_X, 
        name: 'posx',
    },
    {
        target: this.gl().TEXTURE_CUBE_MAP_NEGATIVE_X, 
        name: 'negx',
    },
    {
        target: this.gl().TEXTURE_CUBE_MAP_POSITIVE_Y, 
        name: 'posy',
    },
    {
        target: this.gl().TEXTURE_CUBE_MAP_NEGATIVE_Y, 
        name: 'negy',
    },
    {
        target: this.gl().TEXTURE_CUBE_MAP_POSITIVE_Z, 
        name: 'posz',
    },
    {
        target: this.gl().TEXTURE_CUBE_MAP_NEGATIVE_Z, 
        name: 'negz',
    },
];

this.gl().activeTexture(this.gl().TEXTURE0);
this.gl().bindTexture(this.gl().TEXTURE_CUBE_MAP, tex);
faceInfos.forEach((faceInfo) => {
    makeTexture(faceInfo.target, ImageManager.getImageData(faceInfo.name), this.gl(), tex);
});

this.gl().generateMipmap(this.gl().TEXTURE_CUBE_MAP);
this.gl().texParameteri(
    this.gl().TEXTURE_CUBE_MAP, this.gl().TEXTURE_MIN_FILTER, this.gl().LINEAR_MIPMAP_LINEAR
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// LookAt Setup
///////////////////////////////////////////////////////////////////////////////////////////////////
let eye = vec3.fromValues(0.0, 0.0, 35.0);
let up = vec3.fromValues(0.0, 1.0, 0.0);
let lookAt = vec3.fromValues(0.0, 0.0, -1.0);
let center = vec3.create();
vec3.add(center, eye, lookAt);
let lookAtMat = mat4.create();
mat4.lookAt(lookAtMat, eye, center, up);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Uniforms
///////////////////////////////////////////////////////////////////////////////////////////////////
shaderboy.addUniform3fv("uCameraPos", () => eye);
shaderboy.addUniformMatrix4fv("uLookAt", () => lookAtMat);

let lavaDim = 1.5;
let refrIdx = 1.5;
shaderboy.addUniform3fv("uContainerSize", () => containerDims);
shaderboy.addUniform1f("uContainerRefrIdx", () => refrIdx);

for (let i = 0; i < balls.length; i++) {
	shaderboy.addUniform4f("uLavaInfo[" + i + "]", () => balls[i].getInfo());
}

// add textuer uniform
this.addUniform1i("uEnvirCube", 0, tex, this.gl().TEXTURE_CUBE_MAP);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Parse Input
///////////////////////////////////////////////////////////////////////////////////////////////////
shaderboy.onKeyDown(function(event) {
    switch (event.code) {
        case KEY_MAT_AIR:
			refrIdx = 1.0;
            break;
        case KEY_MAT_WATER:
			refrIdx = 1.3;
            break;
		case KEY_MAT_GLASS:
			refrIdx = 1.5;
            break;
        case KEY_MAT_DIAMOND:
			refrIdx = 2.4;
            break;
    }
});

shaderboy.onMouseWheel(function(event) {
    let tmp = Math.sign(event.deltaY);
    if (tmp < 0) {
        vec3.add(eye, eye, lookAt);
    } else {
        let tmp = vec3.create();
        vec3.negate(tmp, lookAt);
        vec3.add(eye, eye, tmp);
    }
});

///////////////////////////////////////////////////////////////////////////////////////////////////
// Callbacks
///////////////////////////////////////////////////////////////////////////////////////////////////
function clamp(x, minVal, maxVal) {
	return Math.min(Math.max(x, minVal), maxVal);
}

function smoothstep(low, high, value) {
	let t = clamp((value - low) / (high - low), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// https://stackoverflow.com/questions/1458633/how-to-deal-with-floating-point-number-precision-in-javascript
function precise(x) {
	return Number.parseFloat(x).toPrecision(4);
}

function emitBall(size) {
    for (let i = 1; i < balls.length; i++) {
        if (balls[i].s == 0.0) {
            balls[i].s = size;
            balls[i].temp = balls[0].temp;
            balls[0].s -= size;
            balls[0].temp -= 25.0 * balls[0].s;
            balls[i].posMax[0] = Math.random() * 5.0 * (Math.random() * 2.0 - 1.0);           
            balls[i].posMax[2] = Math.random() * 5.0 * (Math.random() * 2.0 - 1.0);
            break;
        }
    }
}

function consumeBall(i) {
    balls[0].s += balls[i].s;
    balls[i].s = 0.0;
    balls[0].temp = Math.floor(balls[0].temp * 0.5 + balls[i].temp * 0.5);
	balls[i].temp = balls[0].temp;
}

// Object movement
this.addFrameCallback(function(renderer) {
    if (
        precise(balls[0].temp) >= 35.0
    ) {
		emitBall(balls[0].s);
    } else if (
        precise(balls[0].temp) == 33.0 && 
		balls[0].s >= 0.4 && Math.random() >= 0.5
    ) {
		emitBall(0.4);
    } else if (
        precise(balls[0].temp) == 30.0 && 
		balls[0].s >= 0.3 && Math.random() >= 0.5
    ) {
		emitBall(0.3);
    } else if (
        precise(balls[0].temp) == 27.0 &&
        balls[0].s >= 0.2 && Math.random() >= 0.5
    ) {
		emitBall(0.2);
    }
    
    for (let i = 0; i < balls.length; i++) {
       	if (balls[i].s < 0.05) {
            balls[i].temp = 22.0;
            continue;
        }
        
        if (balls[i].pos[1] < -0.8)
	        balls[i].temp += 0.05;
        else if (balls[i].pos[1] > 0.8)
            balls[i].temp -= 0.05;
    }
    
    for (let i = 1; i < balls.length; i++) {
        if (balls[i].s == 0.0)
            continue;
        
        //let t = -Math.abs(balls[i].pos[1]) + 1.0;        
        let t = balls[i].pos[1] * 0.5 + 0.5;
		let t2 = (2 * t - 2 * t * t);
        balls[i].pos[0] = t2 * balls[i].posMax[0];
        balls[i].pos[2] = t2 * balls[i].posMax[2];
        
        if (balls[i].pos[1] < -0.98 && balls[i].temp < 25.0) {
            consumeBall(i);
        }

        // top and bottom 0 and in the middle 1.0
        t = -Math.abs(balls[i].pos[1]) + 1.0;
        let minSpeed = 0.005 / containerDims[1];
        let addSpeed = minSpeed * 3.0;
        let subSpeed = minSpeed * 0.5 * balls[i].s;
        let speed = t * addSpeed + minSpeed - subSpeed;
        
        if (balls[i].temp > 28.0 && balls[i].pos[1] < 0.9) {
            balls[i].pos[1] += speed;
        } else if (balls[i].temp < 25.0 && balls[i].pos[1] > -1.0)
            balls[i].pos[1] -= speed;
    }
});

// Camera movement
this.addFrameCallback(function(renderer) {
	if (shaderboy.keyCode('KeyD')) {
        let rotY = mat4.create();
        mat4.fromYRotation(rotY, 0.01);
        vec3.transformMat4(lookAt, lookAt, rotY);        
        vec3.transformMat4(eye, eye, rotY);

        mat4.targetTo(lookAtMat, eye, lookAt, up);
    }
    if (shaderboy.keyCode('KeyA')) {
        let rotY = mat4.create();
        mat4.fromYRotation(rotY, -0.01);
        vec3.transformMat4(lookAt, lookAt, rotY);        
        vec3.transformMat4(eye, eye, rotY);

        mat4.targetTo(lookAtMat, eye, lookAt, up);
    }
    if (shaderboy.keyCode('KeyS')) {
        if (lookAt[1] > 0.999)
            return;
        let rot = mat4.create();
        let axis = vec3.create();
        vec3.cross(axis, lookAt, up);
        mat4.fromRotation(rot, 0.01, axis);
        vec3.transformMat4(lookAt, lookAt, rot);        
        vec3.transformMat4(eye, eye, rot);

        mat4.targetTo(lookAtMat, eye, lookAt, up);
    }
    if (shaderboy.keyCode('KeyW')) {
        if (lookAt[1] < -0.999)
            return;
        let rot = mat4.create();
        let axis = vec3.create();
        vec3.cross(axis, lookAt, up);
        mat4.fromRotation(rot, -0.01, axis);
        vec3.transformMat4(lookAt, lookAt, rot);        
        vec3.transformMat4(eye, eye, rot);

        mat4.targetTo(lookAtMat, eye, lookAt, up);
    }
});
