import { AppLanguage } from './AppLanguage'
// Keep short campus terms intact without inserting forced line breaks or changing source data.
export class ReadableText {
  private static readonly terms: string[] = [
    '版本号', '版本號', '复现步骤', '重現步驟', '读取诊断', '讀取診斷', '认证票据', '認證票據',
    '手动选择', '手動選擇', '当前学期', '當前學期', '官方校历', '官方校曆', '身份验证', '身分驗證',
    '身份认证', '身份認證', '重新登录', '重新登入', '网络连接', '網路連線', '加载失败', '載入失敗',
    '本地课程', '本地課程', '系统日历', '系統日曆', '成绩单', '成績單',
    '触觉反馈', '觸覺回饋', '高对比度', '高對比度', '代理设置', '代理設定', '收藏', '订阅', '訂閱',
    '最新回复', '最新回覆', '智能总结', '智慧總結', '社区公约', '社群公約', '借阅记录', '借閱紀錄',
    '更新', '替换', '替換', '已选日期', '已選日期',
    '教学周', '教學週', '自动同步', '自動同步', '点按', '點按',
    '图书馆', '圖書館', '教务处', '教務處', '教学楼', '教學樓', '一卡通', '研究生',
    '本科生', '开发者', '開發者', '贡献者', '貢獻者', '实验室', '實驗室', '实验楼', '實驗樓',
    '高等数学', '高等數學', '大学物理', '大學物理', '线性代数', '線性代數', '概率论', '概率論',
    '计算机', '計算機', '人工智能', '人工智慧', '学术交流', '學術交流', '体育锻炼', '體育鍛煉',
    '课程', '課程', '考试', '考試', '成绩', '成績', '学分', '學分', '学期', '學期',
    '校区', '校區', '邯郸', '邯鄲', '江湾', '江灣', '枫林', '楓林', '张江', '張江',
    '宿舍', '寝室', '寢室', '电费', '電費', '余额', '餘額', '权限', '權限', '有效期',
    '空教室', '教室', '人数', '人數', '食堂', '窗口', '排队', '排隊', '供餐', '时段', '時段',
    '空闲', '空閒', '拥挤', '擁擠', '预约', '預約', '借阅', '借閱', '场馆', '場館',
    '通知', '公告', '校园', '校園', '公共服务', '公共服務', '开放', '開放', '安排',
    '国庆节', '國慶節', '服务时间', '服務時間', '重新加载', '重新載入'
  ]

  static resource(value: ResourceStr): string {
    return ReadableText.keepWords(typeof value === 'string' ? value : AppLanguage.text(value))
  }

  static keepWords(value: string): string {
    let result: string = ''
    let offset: number = 0
    while (offset < value.length) {
      let match: string = ''
      for (const term of ReadableText.terms) {
        if (term.length > match.length && value.startsWith(term, offset)) match = term
      }
      if (match.length > 0) {
        result += match.split('').join('\u2060')
        offset += match.length
      } else {
        result += value.charAt(offset)
        offset++
      }
    }
    return result
  }
}
