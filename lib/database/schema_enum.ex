import EctoEnum
defenum(MishkaInstaller.PluginStatusEnum, started: 0, stopped: 1, restarted: 2)
defenum(MishkaInstaller.PluginDependTypeEnum, soft: 0, hard: 1, none: 2)

defenum(MishkaInstaller.ActivitiesTypeEnum,
  section: 0,
  email: 1,
  internal_api: 2,
  external_api: 3,
  html_router: 4,
  api_router: 5,
  db: 6,
  plugin: 7,
  dependency: 8
)

defenum(MishkaInstaller.ContentPriorityEnum, none: 0, low: 1, medium: 2, high: 3, featured: 4)

defenum(MishkaInstaller.ActivitiesSectionEnum,
  blog_post: 0,
  blog_category: 1,
  comment: 2,
  tag: 3,
  other: 4,
  blog_author: 5,
  blog_post_like: 6,
  blog_tag_mapper: 7,
  blog_link: 8,
  blog_tag: 9,
  activity: 10,
  bookmark: 11,
  comment_like: 12,
  notif: 13,
  subscription: 14,
  setting: 15,
  permission: 16,
  role: 17,
  user_role: 18,
  identity: 19,
  user: 20,
  compiling: 21,
  updating: 22
)

defenum(MishkaInstaller.ActivitiesStatusEnum,
  error: 0,
  info: 1,
  warning: 2,
  report: 3,
  throw: 4,
  exit: 5
)

defenum(MishkaInstaller.ActivitiesActionEnum,
  add: 0,
  edit: 1,
  delete: 2,
  destroy: 3,
  read: 4,
  send_request: 5,
  receive_request: 6,
  other: 7,
  auth: 8,
  compiling: 9,
  updating: 10
)

defenum(MishkaInstaller.DependencyEnum, git: 0, hex: 1, path: 2)
defenum(MishkaInstaller.DependencyTypeEnum, none: 0, force_update: 1)
