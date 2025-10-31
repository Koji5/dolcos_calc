module ApplicationHelper
  def bootstrap_class_for(type)
    {
      notice:  "success",
      alert:   "danger",
      error:   "danger",
      warning: "warning",
      info:    "info"
    }[type.to_sym] || type.to_s
  end
  def flash_auto_dismiss?(type)
    %i[notice info].include?(type.to_sym)
  end
end
