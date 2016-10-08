# MCVoiceWave
音频波形
最近在项目中有个需求，公司有一个设备，能够获取音频，音频传输过来，解码后就播放了，需求就是播放时，根据声音进行添加波形动画，网上有一些资源，大多都是用*AVAudioRecorder*的*averagePowerForChannel*方法，获取麦上获取到的音量，然后动画显示，如果是一个PCM码流的话，需要自己获取对应的音量信息，而后显示在动画上了，后面我找了一些资料，把PCM的数据解析出音量信息，然后再显示，效果还可以，发出来参考一下。

先来点基础的知识，首先是采样频率，指每秒钟取得声音样本的次数，采样频率越高，包含的声音信息自然就越多，声音也就越好，频率越高，保存需要的空间也会高，所以不一定越高越好，看实际需求。
采样位宽，即采样值，一般分为8位和16位，可以表示的范围分别是2^8和2^16的区间，区间越大，分辨率也就越大，发出声音大能力也就越强，同样的，位宽越大，需要的空间也就越大。
声道数，分为单声道和双声道，双声道即立体声。

另外一些信息，需要一些理解能力，链接中有详细的过程
**dB = *20×log(data^2)***,data是从PCM中获取到的对应位宽的数据，例如，如果是8位就是一个字节，如果是16位就是2个字节
**Y = *A×sin(2×M_PI×X+Phase)***,X是横坐标，phase是相位
**Y = *(cos(M_PI+2×M_PI×X)+1)/2***,X是0～1之间的一个值

再来分析一下我需求中的一些信息，我的解码后获取到的PCM码流是位宽为16位，采样频率为16KHz的单声道数据，每秒钟的码流解码后的PCM数据会被分为5个包，通过计算，每个包的大小是(16×16000×1/8)/5 ＝ 6400(字节)，在程序中，我们使用的是CADisplayLink的定时刷新功能，以和屏幕一样的刷新频率刷新，也就是60Hz，也就是说，我们应该保持让屏幕每隔1/60秒就更新到一个新数据，所以，解码后，每秒的数据应该被分割成60个音量值，也就是说，五个包，每个包有6400个字节，一个包可以获取到12个音量值，大概每1600/3个字节就得取到一个音量平均值，这样就可以简单的实现在屏幕上显示一段音频波形动画了，不过，要注意的是，虽然每隔1/60秒刷新一个新的数据可以让你的波形得到接近表现真实的音频，但是会导致动画的效果会发生类似抖动的效果，因为，相邻的每个波形直接，音量差异可能比较大，从一个波形到另一个波形的跨度大的话，在切换过去的时候就会出现跳过去的感觉，也就是抖动，解决这种抖动现象需要用到插值，先把从PCM数据取音量的次数降下来，原来每个小包取6400个字节取12个音量值，你改为取4次，也就是，每6400/4=1600字节就取一个音量值，然后两个音量值之间再通过插值的方法，取2个值，我这边直接简单的用一次线性插值取值，这样可以使抖动不那么明显，甚至看不出来，如果还有明显的抖动，可以以此类推，再减少取值数量，增加插值数量。
```
/*音频解码成功后，在主线程中调用updateVolume方法，处理PCM数据获取音频波形需要的信息*/
-(void)OnDecodeAudio:(unsigned char*)data Length:(int)length
{
    if (![_device SupportFunction:FUNCTION_VIDEO]) {
        _isFramePreparedOK = YES;
    }
    if (_progressView.isProgressing) {
        return;
    }
    //输出
    if (_audioPlay) {
        //
        if (_isSpeaking || _isSilence) {
            _audioPlay->Silence(true);
        }
        else{
            _audioPlay->Silence(false);
        }
        //
        if (![_device SupportFunction:FUNCTION_VIDEO]) {
            /*data为PCM数据，长度为length个字节，保存到NSData中方便处理*/
            _audioData = [NSData dataWithBytes:data length:length];
            NSData* copyData = [_audioData copy];
            [self performSelectorOnMainThread:@selector(updateVolume:) withObject:copyData waitUntilDone:NO];
        }
        //NSLog(@"OnDecodeAudio length(%d)",length);
        if (!_audioPlay->Show((char*)data, length)) {
            HHAudioPresent_Destroy(_audioPlay);
            _audioPlay = NULL;
        }
    }
}
-(void)updateVolume:(NSData*)volumeData
{
    if (![_device SupportFunction:FUNCTION_VIDEO]) {
        /*获取PCM中的振幅系数信息*/
        NSArray* ampValueArray = [self pcmToAverageAmplitude:volumeData];
        /*添加到音频波形队列中，且在添加前，进行插值*/
        for (NSInteger i = 0; i < ampValueArray.count; i++) {
            [_voiceWaveView changeVolume:[ampValueArray[i] floatValue]];
        }
    }
}
/*  把获取到的PCM数据进行处理，得到音频振幅系数信息
 *  @param  volumeData  PCM数据
 */
-(NSArray*)pcmToAverageAmplitude:(NSData*)volumeData
{
    NSMutableArray* array = [NSMutableArray array];
    short bufferBytes[volumeData.length/2];
    memcpy(bufferBytes, volumeData.bytes, volumeData.length);
    NSInteger packets = 2;
    // 将 buffer 内容取出，进行平方和运算
    for (int i = 0; i < packets; i++)
    {
        long long pcmSum = 0;
        NSUInteger size = volumeData.length/packets/2;
        for (int j = 0; j < size; j++) {
            pcmSum += bufferBytes[size*i+j]*bufferBytes[size*i+j];
        }
        double mean = pcmSum / size/2;
        double volume = 10*log10(mean);
        double maxVolume = 20*log10(pow(2, 16)-1);
        [array addObject:[NSNumber numberWithDouble:volume/maxVolume]];
    }
    return [array copy];
}
```
某一个音量值上，我们使用贝塞尔曲线来画波形，用CAShapeLayer的遮盖，先在layer上加一条透明的贝塞尔曲线，这个曲线是一条正弦波，频率固定，再加一个相位，然后振幅的话，可以用整个view的高的一半作为最大振幅，把PCM的音量大小，作为最大振幅的百分比，这样，这样，音量变高的时候，出来的波峰波谷就会变大，反之变小，就能够画出想要的效果，最大振幅的百分比是通过以当前音量做分子，以系统可以表示的最大音量为分母得到的，比如，如果是16位位宽的PCM数据的话，最大的音量应该是20×log(1/(2^16-1)=-96.32dB，如果是普通室内的声音，大概在－35dB左右，那振幅百分比就是 36.4% ，表示在图形上，就是会出现一个波峰占了整个View高度36.4%的波形
####MCVoiceWaveView.h
```
//
//  MCVoiceWaveView.h
//  MCVoiceWave
//
//  Created by 朱进林 on 10/8/16.
//  Copyright © 2016 Martin Choo. All rights reserved.
//

#import <UIKit/UIKit.h>

#pragma mark - HHVolumeQueue
@interface MCVolumeQueue : NSObject

-(void)pushVolume:(CGFloat)volume;
-(void)pushVolumeWithArray:(NSArray*)array;
-(CGFloat)popVolume;
-(void)cleanQueue;
@end

#pragma mark - HHVoiceWaveView
@interface MCVoiceWaveView : UIView
/**
 *  添加并初始化波纹视图
 *  parentView:父视图
 */
-(void)showInParentView:(UIView*)parentView;
/**
 *  开始声波动画
 */
-(void)startVoiceWave;
/**
 *  改变音量来改变声波幅度
 *  volume:音量大小
 */
-(void)changeVolume:(CGFloat)volume;
/**
 *  停止声波动画
 */
-(void)stopVoiceWave;
/**
 *  移掉声波
 */
-(void)removeFromParent;
@end
```
####MCVoiceWaveView.m
```
//
//  MCVoiceWaveView.m
//  MCVoiceWave
//
//  Created by 朱进林 on 10/8/16.
//  Copyright © 2016 Martin Choo. All rights reserved.
//

#import "MCVoiceWaveView.h"

#define voiceWaveDisappearDuration 0.25
#define minVolume 0.05
static NSRunLoop* _voiceWaveRunLoop;

#pragma mark - MCVolumeQueue
@interface MCVolumeQueue()

@property (nonatomic, strong) NSMutableArray* volumeArray;
@end
@implementation MCVolumeQueue

-(instancetype)init
{
    self = [super init];
    if (self) {
        self.volumeArray = [NSMutableArray array];
    }
    return self;
}
-(void)pushVolume:(CGFloat)volume
{
    if (volume >= minVolume) {
        [_volumeArray addObject:[NSNumber numberWithFloat:volume]];
    }
}
-(void)pushVolumeWithArray:(NSArray *)array
{
    if (array.count > 0) {
        for (NSInteger i = 0; i < array.count; i++) {
            CGFloat volume = [array[i] floatValue];
            [self pushVolume:volume];
        }
    }
}
-(CGFloat)popVolume
{
    CGFloat volume = -10;
    if (_volumeArray.count > 0) {
        volume = [[_volumeArray firstObject] floatValue];
        [_volumeArray removeObjectAtIndex:0];
    }
    return volume;
}
-(void)cleanQueue
{
    if (_volumeArray) {
        [_volumeArray removeAllObjects];
    }
}
@end

#pragma mark - MCVoiceWaveView
@interface MCVoiceWaveView(){
    CGFloat _idleAmplitude;//最小振幅
    CGFloat _amplitude;//振幅系数，表示音量在屏幕上高度的比例
    CGFloat _density;//X轴粒度，粒度越小，线条越顺
    CGFloat _waveHeight;//波形图所在view的高
    CGFloat _waveWidth;//波形图所在view的宽
    CGFloat _waveMid;//波形图所在view的中点
    CGFloat _maxAmplitude;//最大振幅
    //可以多画几根线，使声波波形看起来更复杂真实
    CGFloat _phase;//初始相位位移
    CGFloat _phaseShift;//_phase累进的相位位移量，造成向前推移的感觉
    CGFloat _frequencyFirst;//firstLine在view上的频率
    CGFloat _frequencySecond;//secondLine在view上的频率
    //
    CGFloat _currentVolume;//音量相关
    CGFloat _lastVolume;
    CGFloat _middleVolume;
    //
    CGFloat _maxWidth;//波纹显示最大宽度
    CGFloat _beginX;//波纹开始坐标
    CGFloat _stopAnimationRatio;//衰减系数,停止后避免音量过大，波纹振幅大，乘以衰减系数
    BOOL _isStopAnimating;//正在进行消失动画
    //
    UIBezierPath* _firstLayerPath;
    UIBezierPath* _secondLayerPath;
}
@property (nonatomic, strong) CADisplayLink* displayLink;
@property (nonatomic, strong) CAShapeLayer* firstShapeLayer;
@property (nonatomic, strong) CAShapeLayer* secondShapeLayer;
@property (nonatomic, strong) CAShapeLayer* fillShapeLayer;
//
@property (nonatomic, strong) UIImageView* firstLine;
@property (nonatomic, strong) UIImageView* secondLine;
@property (nonatomic, strong) UIImageView* fillLayerImage;
//
@property (nonatomic, strong) MCVolumeQueue* volumeQueue;

@end
@implementation MCVoiceWaveView

-(void)setup
{
    _frequencyFirst = 2.0f;//2个周期
    _frequencySecond = 1.8f;//1.6个周期，更平缓，有点周期差，使图像看起来更有错落感
    
    _amplitude = 1.0f;
    _idleAmplitude = 0.01f;
    
    _phase = 0.0f;
    _phaseShift = -0.22f;
    _density = 1.f;
    
    _waveHeight = CGRectGetHeight(self.bounds);
    _waveWidth  = CGRectGetWidth(self.bounds);
    _waveMid    = _waveWidth / 2.0f;
    _maxAmplitude = _waveHeight * 0.5;
    
    _maxWidth = _waveWidth + _density;
    _beginX = 0.0;
    
    _lastVolume = 0.0;
    _currentVolume = 0.0;
    _middleVolume = 0.01;
    _stopAnimationRatio = 1.0;
    
    [_volumeQueue cleanQueue];
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        [self startVoiceWaveThread];
    }
    return self;
}

-(void)dealloc
{
    [_displayLink invalidate];
}

-(void)voiceWaveThreadEntryPoint:(id)__unused object
{
    @autoreleasepool {
        [[NSThread currentThread] setName:@"com.anxin-net.VoiceWave"];
        _voiceWaveRunLoop = [NSRunLoop currentRunLoop];
        [_voiceWaveRunLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [_voiceWaveRunLoop run];
    }
}

-(NSThread*)startVoiceWaveThread
{
    static NSThread* _voiceWaveThread = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _voiceWaveThread = [[NSThread alloc] initWithTarget:self selector:@selector(voiceWaveThreadEntryPoint:) object:nil];
        [_voiceWaveThread start];
    });
    return _voiceWaveThread;
}

-(void)showInParentView:(UIView *)parentView
{
    if (![self.superview isKindOfClass:[parentView class]] || !_isStopAnimating) {
        [parentView addSubview:self];
    }else {
        [self.layer removeAllAnimations];
        return;
    }
    //
    self.frame =CGRectMake(0, 0, parentView.bounds.size.width, parentView.bounds.size.height);
    [self setup];
    //
    [self addSubview:self.firstLine];
    self.firstLine.frame = self.bounds;
    CGFloat firstLineWidth = 5 / [UIScreen mainScreen].scale;
    self.firstShapeLayer = [self generateShaperLayerWithLineWidth:firstLineWidth];
    self.firstLine.layer.mask = self.firstShapeLayer;
    //
    [self addSubview:self.secondLine];
    self.secondLine.frame = self.bounds;
    CGFloat secondLineWidth = 4 / [UIScreen mainScreen].scale;
    self.secondShapeLayer = [self generateShaperLayerWithLineWidth:secondLineWidth];
    self.secondLine.layer.mask = self.secondShapeLayer;
    //
    [self addSubview:self.fillLayerImage];
    _fillLayerImage.frame = self.bounds;
    _fillLayerImage.layer.mask = self.fillShapeLayer;
    //
    [self updateMeters];
}

-(void)startVoiceWave
{
    if (_isStopAnimating) {
        return;
    }
    [self setup];
    if (_voiceWaveRunLoop) {
        [self.displayLink invalidate];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(invokeWaveCallback)];
        [self.displayLink addToRunLoop:_voiceWaveRunLoop forMode:NSRunLoopCommonModes];
    }else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_voiceWaveRunLoop) {
                [self.displayLink invalidate];
                self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(invokeWaveCallback)];
                [self.displayLink addToRunLoop:_voiceWaveRunLoop forMode:NSRunLoopCommonModes];
            }
        });
    }
}

-(void)stopVoiceWave
{
    if (_isStopAnimating) {
        return;
    }
    [self.layer removeAllAnimations];
    _isStopAnimating = YES;
}

-(void)changeVolume:(CGFloat)volume
{
    @synchronized (self) {
        _lastVolume = _currentVolume;
        _currentVolume = volume;
        //
        NSArray* volumeArray = [self generatePointsOfSize:6 withPowFactor:1 fromStartY:_lastVolume toEndY:_currentVolume];
        [self.volumeQueue pushVolumeWithArray:volumeArray];
    }
}

-(void)removeFromParent
{
    [_displayLink invalidate];
    [self removeFromSuperview];
}

-(void)invokeWaveCallback
{
    [self updateMeters];
}

-(void)updateMeters
{
    CGFloat volume = [self.volumeQueue popVolume];
    if (volume > 0) {
        _middleVolume = volume;
    }else {
        _middleVolume -= 0.01;
    }
    _phase += _phaseShift;
    _amplitude = fmax(_middleVolume, _idleAmplitude);
    if (_isStopAnimating) {
        _stopAnimationRatio -=0.05;
        _stopAnimationRatio = fmax(_stopAnimationRatio, 0.01);
        if (_stopAnimationRatio == 0.01) {
            [self animationStopped];
        }
    }
    _firstLayerPath = nil;
    _secondLayerPath = nil;
    _firstLayerPath = [self generateBezierPathWithFrequency:_frequencyFirst maxAmplitude:_maxAmplitude phase:_phase];
    _secondLayerPath = [self generateBezierPathWithFrequency:_frequencySecond maxAmplitude:_maxAmplitude * 0.8 phase:_phase+3];
    //
    NSDictionary* dic = @{@"firstPath":_firstLayerPath,@"secondPath":_secondLayerPath};
    [self performSelectorOnMainThread:@selector(updateShapeLayerPath:) withObject:dic waitUntilDone:NO];
}

-(void)updateShapeLayerPath:(NSDictionary*)dic
{
    UIBezierPath* firstPath = [dic objectForKey:@"firstPath"];
    _firstShapeLayer.path = firstPath.CGPath;
    UIBezierPath* secondPath = [dic objectForKey:@"secondPath"];
    _secondShapeLayer.path = secondPath.CGPath;
    if (firstPath && secondPath) {
        UIBezierPath* fillPath = [UIBezierPath bezierPathWithCGPath:firstPath.CGPath];
        [fillPath appendPath:secondPath];
        [fillPath closePath];
        _fillShapeLayer.path = fillPath.CGPath;
    }
}

-(void)animationStopped
{
    [self.displayLink invalidate];
    _isStopAnimating = NO;
    //
    self.layer.mask = nil;
    _lastVolume = 0.0;
    _currentVolume = 0.0;
    _middleVolume = 0.05;
    [_volumeQueue cleanQueue];
}

#pragma mark - generate
-(CAShapeLayer*)generateShaperLayerWithLineWidth:(CGFloat)lineWidth
{
    CAShapeLayer* waveLine = [CAShapeLayer layer];
    waveLine.lineCap = kCALineCapButt;
    waveLine.lineJoin = kCALineJoinRound;
    waveLine.strokeColor = [UIColor redColor].CGColor;
    waveLine.fillColor = [UIColor clearColor].CGColor;
    waveLine.lineWidth = lineWidth;
    waveLine.backgroundColor = [UIColor clearColor].CGColor;
    return  waveLine;
}
/** 根据频率，最大振幅，相位等信息，得到代表当前音量的波形
 */
-(UIBezierPath*)generateBezierPathWithFrequency:(CGFloat)frequency maxAmplitude:(CGFloat)maxAmplitude phase:(CGFloat)phase
{
    UIBezierPath* waveLinePath = [UIBezierPath bezierPath];
    CGFloat normedAmplitude = fmin(_amplitude, 1.0);//振幅百分比，最高只能是1
    //按X轴粒度连接多个点，拼接在一起，形成类似曲线的波形
    for (CGFloat x = _beginX; x < _maxWidth; x += _density) {
        CGFloat scaling = (1+cosf(M_PI+(x/_maxWidth)*2*M_PI))/2;
        CGFloat y = scaling * _maxAmplitude * normedAmplitude * _stopAnimationRatio * sinf(2 * M_PI * (x / _waveWidth) * frequency + phase) + (_waveHeight * 0.5);
        if (_beginX == x) {
            [waveLinePath moveToPoint:CGPointMake(x, y)];
        }else {
            [waveLinePath addLineToPoint:CGPointMake(x, y)];
        }
    }
    return waveLinePath;
}
/**插值方法，在相邻的两个值中间，插入若干个值，使波形切换时过渡更平滑*/
-(NSArray*)generatePointsOfSize:(NSInteger)size withPowFactor:(CGFloat)factor fromStartY:(CGFloat)startY toEndY:(CGFloat)endY
{
    BOOL factorValid = factor < 2 && factor > 0 && factor != 0;
    BOOL startYValid = 0 <= startY && startY <= 1;
    BOOL endYValid = 0 <= endY && endY <= 1;
    if (!(factorValid && startYValid && endYValid)) {
        return nil;
    }
    //
    NSMutableArray* mArray = [NSMutableArray arrayWithCapacity:size];
    CGFloat startX,endX;
    startX = pow(startY, 1/factor);
    endX = pow(endY, 1/factor);
    //
    CGFloat pieceOfX = (endX - startX) / size;
    CGFloat x,y;
    [mArray addObject:[NSNumber numberWithFloat:startY]];
    for (int i = 1; i < size; ++i) {
        x = startX + pieceOfX * i;
        y = pow(x, factor);
        [mArray addObject:[NSNumber numberWithFloat:y]];
    }
    return [mArray copy];
}
#pragma mark - getter
-(UIImageView*)firstLine
{
    if (!_firstLine) {
        self.firstLine = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pic_firstLine.png"]];
        _firstLine.layer.masksToBounds = YES;
    }
    return _firstLine;
}
-(UIImageView*)secondLine
{
    if (!_secondLine) {
        self.secondLine = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pic_secondLine.png"]];
        _secondLine.layer.masksToBounds = YES;
        _secondLine.alpha = 0.6;
    }
    return _secondLine;
}
-(UIImageView*)fillLayerImage
{
    if (!_fillLayerImage) {
        self.fillLayerImage = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"pic_fill.png"]];
        _fillLayerImage.layer.masksToBounds = YES;
        _fillLayerImage.alpha = 0.2;
    }
    return _fillLayerImage;
}
-(CAShapeLayer*)fillShapeLayer
{
    if (!_fillShapeLayer) {
        self.fillShapeLayer = [CAShapeLayer layer];
        _fillShapeLayer.lineCap = kCALineCapButt;
        _fillShapeLayer.lineJoin = kCALineJoinRound;
        _fillShapeLayer.strokeColor = [UIColor clearColor].CGColor;
        _fillShapeLayer.fillColor = [UIColor redColor].CGColor;
        _fillShapeLayer.fillRule = @"even-odd";
        _fillShapeLayer.lineWidth = 2;
        _fillShapeLayer.backgroundColor = [UIColor clearColor].CGColor;
    }
    return _fillShapeLayer;
}
-(MCVolumeQueue*)volumeQueue
{
    if (!_volumeQueue) {
        self.volumeQueue = [[MCVolumeQueue alloc] init];
    }
    return _volumeQueue;
}
@end
```
以上部分代码涉及公司机密，不方便把全部源码贴出，我在***Github上贴出的是通过捕捉麦克风输入的音频的波形***，如果有改进建议或者疑问的话，可以联系我，感谢分享！
效果图：
![效果图1.gif](http://upload-images.jianshu.io/upload_images/2936611-c9b94f268e139d1d.gif?imageMogr2/auto-orient/strip)
这是用AVAudioRecord获取麦克风的音频，获取PCM数据进行处理后，得到的效果图如下：
![效果图2.gif](http://upload-images.jianshu.io/upload_images/2936611-d56103aaf279a9ea.gif?imageMogr2/auto-orient/strip)

参考链接
音量分贝计算资料：http://www.cnblogs.com/karlchen/archive/2007/04/10/707478.html
贝塞尔曲线：http://blog.csdn.net/likendsl/article/details/7852658
附上[函数图像绘制工具](http://zh.numberempire.com/graphingcalculator.php)
