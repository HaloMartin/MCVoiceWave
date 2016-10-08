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
